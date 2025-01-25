import gleam/bit_array
import gleam/dict
import gleam/list
import gleeunit
import gleeunit/should
import simplifile

import bencode/bencode
import torrent

pub fn main() {
  gleeunit.main()
}

pub fn decode_string_test() {
  "11:Hello world"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_ok()
  |> should.equal("Hello world" |> bencode.String)
}

pub fn handle_string_length_too_long_test() {
  "12:Hello world"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_error()
  |> should.equal(bencode.OutOfBounds)
}

pub fn handle_string_no_separator_test() {
  "11Hello world"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_error()
  |> should.equal(bencode.OutOfBounds)
}

pub fn handle_string_invalid_string_length_test() {
  "11a:Hello world"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_error()
  |> should.equal(bencode.OutOfBounds)
}

pub fn decode_positive_integer_test() {
  "i42e"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_ok()
  |> should.equal(42 |> bencode.Int)
}

pub fn decode_negative_integer_test() {
  "i-42e"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_ok()
  |> should.equal(-42 |> bencode.Int)
}

pub fn handle_integer_unclosed_test() {
  "i42a"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_error()
  |> should.equal(bencode.UnclosedTerm)
}

pub fn handle_integer_invalid_test() {
  "i42ae"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_error()
  |> should.equal(bencode.UnclosedTerm)
}

pub fn decode_list_test() {
  "li42ei-42ee"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_ok()
  |> should.equal([42, -42] |> list.map(bencode.Int) |> bencode.List)
}

pub fn handle_list_unclosed_test() {
  "li42ei42e"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_error()
  |> should.equal(bencode.Unexpected("EOF"))
}

pub fn decode_dict_test() {
  "di42ei-42ee"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_ok()
  |> should.equal(
    dict.from_list([#(42 |> bencode.Int, -42 |> bencode.Int)])
    |> bencode.Dict,
  )
}

pub fn handle_dict_unclosed_test() {
  "di42ei42e"
  |> bit_array.from_string
  |> bencode.decode
  |> should.be_error()
  |> should.equal(bencode.Unexpected("EOF"))
}

pub fn void_torrent_file_test() {
  let path = "./test/void-linux.torrent"

  let assert Ok(content) = simplifile.read_bits(path)
  let assert Ok(torrent) = bencode.decode(content)

  let assert Ok(decoded) = torrent.from_bencode(torrent)
  let encoded = torrent.to_bencode(decoded) |> bencode.encode

  should.equal(content, encoded)
}
