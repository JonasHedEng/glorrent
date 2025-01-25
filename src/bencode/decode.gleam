import gleam/bool
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result

import bencode/bencode.{type Value}

pub type DecodeError {
  DecodeError(expected: String, found: String)
}

pub opaque type Decoder(t) {
  Decoder(function: fn(Value) -> #(t, List(DecodeError)))
}

pub fn success(data: t) -> Decoder(t) {
  Decoder(function: fn(_) { #(data, []) })
}

pub const int: Decoder(Int) = Decoder(decode_int)

fn decode_int(value: Value) -> #(Int, List(DecodeError)) {
  run_decode_function(value, "Int", do_decode_int)
}

fn do_decode_int(value: Value) {
  case value {
    bencode.Int(num) -> Ok(num)
    _ -> Error(0)
  }
}

pub const string: Decoder(String) = Decoder(decode_string)

fn decode_string(value: Value) -> #(String, List(DecodeError)) {
  run_decode_function(value, "String", do_decode_string)
}

fn do_decode_string(value: Value) {
  case value {
    bencode.String(str) -> Ok(str)
    _ -> Error("")
  }
}

pub const bytes: Decoder(BitArray) = Decoder(decode_bytes)

fn decode_bytes(value: Value) -> #(BitArray, List(DecodeError)) {
  run_decode_function(value, "BitArray", do_decode_bytes)
}

fn do_decode_bytes(value: Value) {
  case value {
    bencode.Bytes(bytes) -> Ok(bytes)
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
  value: Value,
  item: fn(Value) -> #(t, List(DecodeError)),
) -> #(List(t), List(DecodeError)) {
  let #(items, errors) = case value {
    bencode.List(items) -> #(items, [])
    _ -> #([], [DecodeError("List", bencode.classify(value))])
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
  value: Value,
  key: fn(Value) -> #(k, List(DecodeError)),
  val: fn(Value) -> #(v, List(DecodeError)),
) -> #(Dict(k, v), List(DecodeError)) {
  let #(entries, errors) = case value {
    bencode.Dict(entries) -> #(entries |> dict.to_list, [])
    _ -> #([], [DecodeError("List", bencode.classify(value))])
  }

  list.map(entries, fn(entry) {
    let #(k, kerr) = key(entry.0)
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
      bencode.Dict(d) -> Ok(d)
      _ -> Error(Nil)
    }

    let #(out, errors1) = {
      let val = result.then(as_dict, dict.get(_, bencode.String(key)))
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

fn run_decode_function(
  value: Value,
  name: String,
  f: fn(Value) -> Result(t, t),
) -> #(t, List(DecodeError)) {
  case f(value) {
    Ok(data) -> #(data, [])
    Error(default) -> #(default, [DecodeError(name, bencode.classify(value))])
  }
}

fn run_decoders(
  value: Value,
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

pub fn run(value: Value, decoder: Decoder(t)) -> Result(t, List(DecodeError)) {
  let #(maybe_invalid_data, errors) = decoder.function(value)
  case errors {
    [] -> Ok(maybe_invalid_data)
    _ -> Error(errors)
  }
}
