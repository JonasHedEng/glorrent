import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result

import beencode.{type BValue}

pub type DecodeError {
  DecodeError(expected: String, found: String)
}

pub opaque type Decoder(t) {
  Decoder(function: fn(BValue) -> #(t, List(DecodeError)))
}

pub fn success(data: t) -> Decoder(t) {
  Decoder(function: fn(_) { #(data, []) })
}

fn classify(value: BValue) {
  case value {
    beencode.BInt(_) -> "Int"
    beencode.BString(_) -> "String"
    beencode.BList(_) -> "List"
    beencode.BDict(_) -> "Dict"
  }
}

pub fn failure(zero: a, expected: String) -> Decoder(a) {
  Decoder(function: fn(d) { #(zero, [DecodeError(expected, classify(d))]) })
}

pub const int: Decoder(Int) = Decoder(decode_int)

fn decode_int(value: BValue) -> #(Int, List(DecodeError)) {
  run_decode_function(value, "Int", do_decode_int)
}

fn do_decode_int(value: BValue) {
  case value {
    beencode.BInt(num) -> Ok(num)
    _ -> Error(0)
  }
}

pub const string: Decoder(String) = Decoder(decode_string)

fn decode_string(value: BValue) -> #(String, List(DecodeError)) {
  run_decode_function(value, "String", do_decode_string)
}

fn do_decode_string(value: BValue) {
  case value {
    beencode.BString(bytes) -> {
      bytes |> bit_array.to_string |> result.replace_error("")
    }
    _ -> Error("")
  }
}

pub const bytes: Decoder(BitArray) = Decoder(decode_bytes)

fn decode_bytes(value: BValue) -> #(BitArray, List(DecodeError)) {
  run_decode_function(value, "BitArray", do_decode_bytes)
}

fn do_decode_bytes(value: BValue) {
  case value {
    beencode.BString(bytes) -> Ok(bytes)
    _ -> Error(<<>>)
  }
}

pub fn list(of inner: Decoder(t)) -> Decoder(List(t)) {
  Decoder(fn(value) {
    let #(l, errs) = decode_list(value, inner.function)
    #(list.reverse(l), errs)
  })
}

fn decode_list(
  value: BValue,
  item: fn(BValue) -> #(t, List(DecodeError)),
) -> #(List(t), List(DecodeError)) {
  let #(items, errors) = case value {
    beencode.BList(items) -> #(items, [])
    _ -> #([], [DecodeError("List", classify(value))])
  }

  list.map(items, item)
  |> list.fold(#([], errors), fn(acc, iter) {
    let #(vals, errs) = acc
    let #(val, err) = iter

    use <- bool.guard(list.length(err) > 0, #([], list.append(err, errs)))
    #([val, ..vals], errs)
  })
}

pub fn dict(key key: Decoder(a), value val: Decoder(b)) -> Decoder(Dict(a, b)) {
  Decoder(fn(value) { decode_dict(value, key.function, val.function) })
}

fn decode_dict(
  value: BValue,
  key: fn(BValue) -> #(k, List(DecodeError)),
  val: fn(BValue) -> #(v, List(DecodeError)),
) -> #(Dict(k, v), List(DecodeError)) {
  let #(entries, errors) = case value {
    beencode.BDict(entries) -> #(entries |> dict.to_list, [])
    _ -> #([], [DecodeError("List", classify(value))])
  }

  list.map(entries, fn(entry) {
    let #(k, kerr) = key(beencode.BString(entry.0))
    let #(v, verr) = val(entry.1)

    #(#(k, v), list.append(kerr, verr))
  })
  |> list.fold(#(dict.new(), errors), fn(acc, iter) {
    let #(pairs, errs) = acc
    let #(pair, err) = iter
    let #(k, v) = pair

    use <- bool.guard(list.length(err) > 0, #(
      dict.new(),
      list.append(err, errs),
    ))
    #(dict.insert(pairs, k, v), errs)
  })
}

pub fn field(
  key: String,
  of inner: Decoder(t),
  next then: fn(t) -> Decoder(final),
) -> Decoder(final) {
  Decoder(fn(value) {
    let as_dict = case value {
      beencode.BDict(d) -> Ok(d)
      _ -> Error(Nil)
    }

    let #(out, errors1) = {
      let val = result.then(as_dict, dict.get(_, key |> bit_array.from_string))
      case val {
        Ok(val) -> inner.function(val)
        _ -> inner.function(value)
      }
    }
    let #(out, errors2) = then(out).function(value)
    #(out, list.append(errors1, errors2))
  })
}

pub fn one_of(
  first: Decoder(a),
  or alternatives: List(Decoder(a)),
) -> Decoder(a) {
  Decoder(function: fn(value) {
    let #(_, errors) as layer = first.function(value)
    case errors {
      [] -> layer
      _ -> run_decoders(value, layer, alternatives)
    }
  })
}

pub fn optional(inner: Decoder(t)) -> Decoder(option.Option(t)) {
  Decoder(function: fn(value) {
    let #(decoded, errors) = inner.function(value)
    case errors {
      [] -> #(option.Some(decoded), [])
      _ -> #(option.None, [])
    }
  })
}

pub fn then(first: Decoder(t), do f: fn(t) -> Decoder(final)) -> Decoder(final) {
  Decoder(function: fn(value) {
    let #(data, errors) = first.function(value)
    let decoder = f(data)
    let #(data, _) as layer = decoder.function(value)
    case errors {
      [] -> layer
      _ -> #(data, errors)
    }
  })
}

fn run_decode_function(
  value: BValue,
  name: String,
  f: fn(BValue) -> Result(t, t),
) -> #(t, List(DecodeError)) {
  case f(value) {
    Ok(data) -> #(data, [])
    Error(default) -> #(default, [DecodeError(name, classify(value))])
  }
}

fn run_decoders(
  value: BValue,
  failure: #(t, List(DecodeError)),
  decoders: List(Decoder(t)),
) -> #(t, List(DecodeError)) {
  case decoders {
    [] -> failure

    [decoder, ..decoders] -> {
      let #(_, errors) as layer = decoder.function(value)
      case errors {
        [] -> layer
        _ -> run_decoders(value, failure, decoders)
      }
    }
  }
}

pub fn run(value: BValue, decoder: Decoder(t)) -> Result(t, List(DecodeError)) {
  let #(maybe_invalid_data, errors) = decoder.function(value)
  case errors {
    [] -> Ok(maybe_invalid_data)
    _ -> Error(errors)
  }
}
