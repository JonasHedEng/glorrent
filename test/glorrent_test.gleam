import gleam/dict
import gleam/list
import gleeunit
import gleeunit/should
import simplifile

import beencode
import torrent

pub fn main() {
  gleeunit.main()
}

// TODO: Manual testing towards this fantastic service: https://torrentdyne.com/

pub fn void_torrent_file_test() {
  let path = "./example-torrents/void-linux.torrent"

  let assert Ok(content) = simplifile.read_bits(path)
  let assert Ok(torrent) = beencode.decode(content)

  let assert Ok(decoded) = torrent.from_bencode(torrent)
  let encoded = torrent.to_bencode(decoded) |> beencode.encode

  should.equal(content, encoded)
}

pub fn void_piece_map_test() {
  let path = "./example-torrents/void-linux.torrent"

  let assert Ok(content) = simplifile.read_bits(path)
  let assert Ok(bencode) = beencode.decode(content)
  let assert Ok(torrent) = torrent.from_bencode(bencode)

  let piece_map = torrent.get_piece_map(torrent.info)

  let uneven_pieces =
    dict.to_list(piece_map)
    |> list.flat_map(fn(entry) {
      let #(_i, #(_hash, file_pieces)) = entry
      file_pieces
    })
    |> list.filter(fn(piece) { piece.length != 524_288 })

  should.equal(1526, piece_map |> dict.size)
  should.equal([], uneven_pieces)
}

pub fn tears_piece_map_test() {
  let path = "./example-torrents/tears-of-steel.torrent"

  let assert Ok(content) = simplifile.read_bits(path)
  let assert Ok(bencode) = beencode.decode(content)
  let assert Ok(torrent) = torrent.from_bencode(bencode)

  let piece_map = torrent.get_piece_map(torrent.info)

  let files =
    dict.to_list(piece_map)
    |> list.flat_map(fn(entry) {
      let #(_i, #(_hash, file_pieces)) = entry
      file_pieces |> list.map(fn(piece) { #(piece.path, Nil) })
    })
    // Deduplicate
    |> dict.from_list
    |> dict.to_list
    |> list.map(fn(pair) { pair.0 })

  should.equal(1090, piece_map |> dict.size)
  should.equal(
    [
      ["Tears of Steel.de.srt"],
      ["Tears of Steel.en.srt"],
      ["Tears of Steel.es.srt"],
      ["Tears of Steel.fr.srt"],
      ["Tears of Steel.it.srt"],
      ["Tears of Steel.nl.srt"],
      ["Tears of Steel.no.srt"],
      ["Tears of Steel.ru.srt"],
      ["Tears of Steel.webm"],
      ["poster.jpg"],
    ],
    files,
  )
}
