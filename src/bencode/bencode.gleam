import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/string

pub type Value {
  Int(Int)
  String(String)
  Bytes(BitArray)
  List(List(Value))
  Dict(Dict(Value, Value))
}

type Ctx {
  Ctx(src: BitArray, pos: Int)
}

pub type DecodeError {
  UnclosedTerm
  InvalidNumber
  InvalidInteger
  Unexpected(String)
  OutOfBounds
}

pub type DecodeResult =
  Result(#(Ctx, Value), DecodeError)

type Formatting {
  Fmt(indent: String, depth: Int, binary: Bool)
}

pub fn classify(value) {
  case value {
    Int(_) -> "Int"
    String(_) -> "String"
    Bytes(_) -> "Bytes"
    List(_) -> "List"
    Dict(_) -> "Dict"
  }
}

pub fn pretty_format(value: Value) -> String {
  let benc = do_encode(value, Fmt("  ", 0, False))

  let assert Ok(benc_as_str) = bit_array.to_string(benc)
  benc_as_str
}

pub fn encode(value: Value) -> BitArray {
  do_encode(value, Fmt("", 0, True))
}

fn do_encode_bytes(bytes: BitArray, write_binary: Bool) {
  let size = bit_array.byte_size(bytes) |> int.to_string

  case write_binary {
    False -> { size <> ":<binary blob>" } |> bit_array.from_string
    True ->
      { size <> ":" }
      |> bit_array.from_string
      |> bit_array.append(bytes)
  }
}

fn cmp(val_a: Value, val_b: Value) {
  case val_a, val_b {
    Int(a), Int(b) -> int.compare(a, b)
    String(a), String(b) -> string.compare(a, b)
    Bytes(a), Bytes(b) -> bit_array.compare(a, b)
    _, _ -> order.Eq
  }
}

fn do_encode(value: Value, fmt: Formatting) -> BitArray {
  let inner = case value {
    Int(num) -> {
      { "i" <> num |> int.to_string <> "e" } |> bit_array.from_string
    }
    String(str) -> {
      do_encode_bytes(str |> bit_array.from_string, True)
    }
    Bytes(bytes) -> {
      do_encode_bytes(bytes, fmt.binary)
    }
    Dict(pairs) -> {
      let inner =
        pairs
        |> dict.to_list
        |> list.sort(by: fn(a, b) { cmp(a.0, b.0) })
        |> list.map(fn(pair) {
          let #(k, v) = pair
          let key = do_encode(k, Fmt(..fmt, depth: fmt.depth + 1))
          let value = do_encode(v, Fmt(..fmt, depth: fmt.depth + 2))
          bit_array.append(key, value)
        })
        |> bit_array.concat

      case fmt.indent {
        "" -> bit_array.concat([<<"d">>, inner, <<"e">>])
        _ -> {
          let close = string.repeat(fmt.indent, fmt.depth) <> "e"
          bit_array.concat([<<"d\n">>, inner, bit_array.from_string(close)])
        }
      }
    }

    List(items) -> {
      let inner =
        items
        |> list.map(do_encode(_, Fmt(..fmt, depth: fmt.depth + 1)))
        |> bit_array.concat

      case fmt.indent {
        "" -> bit_array.concat([<<"l">>, inner, <<"e">>])
        _ -> {
          let close = string.repeat(fmt.indent, fmt.depth) <> "e"
          bit_array.concat([<<"l\n">>, inner, bit_array.from_string(close)])
        }
      }
    }
  }

  case fmt.indent {
    "" -> inner
    _ ->
      bit_array.concat([
        <<string.repeat(fmt.indent, fmt.depth):utf8>>,
        inner,
        <<"\n">>,
      ])
  }
}

pub fn decode(src: BitArray) -> Result(Value, DecodeError) {
  let ctx = Ctx(src:, pos: 0)

  case do_decode(ctx) {
    Ok(#(Ctx(src: <<>>, ..), value)) -> Ok(value)
    Ok(#(Ctx(src: <<char:utf8_codepoint>>, ..), _)) ->
      Error(Unexpected(string.from_utf_codepoints([char])))
    Ok(#(Ctx(_, _), _)) -> Error(Unexpected("?"))
    Error(error) -> Error(error)
  }
}

fn adv(ctx: Ctx, src: BitArray, by size: Int) {
  Ctx(src: src, pos: ctx.pos + size)
}

fn do_decode(ctx: Ctx) -> DecodeResult {
  case ctx.src {
    <<"i":utf8, rest:bytes>> -> ctx |> adv(rest, 1) |> do_decode_integer
    <<"l":utf8, rest:bytes>> -> ctx |> adv(rest, 1) |> decode_list
    <<"d":utf8, rest:bytes>> -> ctx |> adv(rest, 1) |> decode_dict
    // starts with a digit
    <<digit, _:bytes>> if 48 <= digit && digit <= 57 -> do_decode_string(ctx)
    <<>> -> Error(Unexpected("EOF"))
    rest -> Error(Unexpected(rest |> bit_array.to_string |> result.unwrap("?")))
  }
}

fn do_decode_integer(ctx: Ctx) -> DecodeResult {
  let #(prefix, ctx) = case ctx.src {
    <<"-":utf8, rest:bytes>> -> #(
      "-" |> string.to_utf_codepoints,
      ctx |> adv(rest, 1),
    )
    _ -> #([], ctx)
  }
  use #(ctx, num) <- result.try(parse_number(ctx, prefix))

  case ctx.src {
    <<"e", rest:bytes>> -> Ok(#(ctx |> adv(rest, 1), Int(num)))
    <<>> -> Error(Unexpected("EOF"))
    _ -> Error(UnclosedTerm)
  }
}

fn parse_number(
  ctx: Ctx,
  acc: List(UtfCodepoint),
) -> Result(#(Ctx, Int), DecodeError) {
  case ctx.src {
    <<digit, rest:bytes>> if 48 <= digit && digit <= 57 -> {
      let assert Ok(codepoint) = string.utf_codepoint(digit)
      parse_number(ctx |> adv(rest, 1), [codepoint, ..acc])
    }
    _ if acc == [] -> {
      Error(InvalidNumber)
    }
    _ -> {
      let assert Ok(num_str) =
        acc
        |> list.reverse
        |> string.from_utf_codepoints
        |> int.parse

      Ok(#(ctx, num_str))
    }
  }
}

fn do_decode_string(ctx: Ctx) -> DecodeResult {
  use #(ctx, length) <- result.try(parse_number(ctx, []))

  case ctx.src {
    <<":", content:bytes-size(length), rest:bytes>> -> {
      let value = case bit_array.to_string(content) {
        Ok(str) -> String(str)
        Error(Nil) -> Bytes(content)
      }

      Ok(#(ctx |> adv(rest, by: length + 1), value))
    }
    _ -> Error(OutOfBounds)
  }
}

fn decode_list(ctx: Ctx) -> DecodeResult {
  use #(ctx, items) <- result.map(do_decode_list(ctx, []))

  #(ctx, List(items |> list.reverse))
}

fn do_decode_list(
  ctx: Ctx,
  acc: List(Value),
) -> Result(#(Ctx, List(Value)), DecodeError) {
  use #(ctx, value) <- result.try(do_decode(ctx))

  case ctx.src {
    <<"e":utf8, rest:bytes>> -> Ok(#(ctx |> adv(rest, 1), [value, ..acc]))
    _ -> do_decode_list(ctx, [value, ..acc])
  }
}

fn decode_dict(ctx: Ctx) -> DecodeResult {
  use #(ctx, pairs) <- result.map(do_decode_dict(ctx, []))

  #(ctx, Dict(pairs |> list.reverse |> dict.from_list))
}

fn do_decode_dict(
  ctx: Ctx,
  acc: List(#(Value, Value)),
) -> Result(#(Ctx, List(#(Value, Value))), DecodeError) {
  use #(ctx, key) <- result.try(do_decode(ctx))
  use #(ctx, value) <- result.try(do_decode(ctx))

  case ctx.src {
    <<"e":utf8, rest:bytes>> ->
      Ok(#(ctx |> adv(rest, 1), [#(key, value), ..acc]))
    _ -> do_decode_dict(ctx, [#(key, value), ..acc])
  }
}
