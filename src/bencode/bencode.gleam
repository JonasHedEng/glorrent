import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/string

import beencode.{type BValue}

type Formatting {
  Fmt(indent: String, depth: Int, include_binary: Bool)
}

pub fn pretty(value: BValue) -> String {
  let benc = do_encode(value, Fmt("  ", 0, False))

  let assert Ok(benc_as_str) = bit_array.to_string(benc)
  benc_as_str
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

fn do_encode(value: BValue, fmt: Formatting) -> BitArray {
  let inner = case value {
    beencode.BInt(num) -> {
      { "i" <> num |> int.to_string <> "e" } |> bit_array.from_string
    }
    beencode.BString(bytes) -> {
      let valid_string = bit_array.is_utf8(bytes)
      do_encode_bytes(bytes, valid_string || fmt.include_binary)
    }
    beencode.BDict(pairs) -> {
      let inner =
        pairs
        |> dict.to_list
        |> list.sort(by: fn(a, b) { bit_array.compare(a.0, b.0) })
        |> list.map(fn(pair) {
          let #(k, v) = pair
          let key =
            do_encode(beencode.BString(k), Fmt(..fmt, depth: fmt.depth + 1))
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

    beencode.BList(items) -> {
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
