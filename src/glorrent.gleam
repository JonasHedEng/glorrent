import gleam/io
import gleam/result

import simplifile

import bencode/bencode
import bencode/decode
import torrent.{type Torrent}

pub type Error {
  FileError(simplifile.FileError)
  DecodeError(bencode.DecodeError)
  InvalidFile(msg: String, causes: List(decode.DecodeError))
}

fn parse_torrent_file(at path: String) -> Result(Torrent, Error) {
  use content <- result.try(
    simplifile.read_bits(path) |> result.map_error(FileError),
  )
  use torrent <- result.try(
    bencode.decode(content) |> result.map_error(DecodeError),
  )

  torrent.from_bencode(torrent)
  |> result.map_error(InvalidFile(
    msg: "Invalid torrent file: " <> path,
    causes: _,
  ))
}

pub fn main() {
  let path = "./void-linux.torrent"

  // use content <- result.try(
  //   simplifile.read_bits(path) |> result.map_error(FileError),
  // )
  // use torrent <- result.try(
  //   bencode.decode(content) |> result.map_error(DecodeError),
  // )

  // torrent
  // |> bencode.pretty_format
  // |> result.unwrap("")
  // |> io.println

  use torrent <- result.try(parse_torrent_file(path))

  let enc_torr =
    torrent
    |> torrent.to_bencode
  let _ =
    simplifile.write_bits(
      path <> ".clone",
      enc_torr
        |> bencode.encode,
    )

  io.println(enc_torr |> bencode.pretty_format)
  // let info_dyn_dict =
  //   torrent.info
  //   |> info_to_bencode
  // use info_enc <- result.try(
  //   info_dyn_dict
  //   |> bencode.encode
  //   |> io.debug
  //   |> result.map_error(fn(errs) { string.inspect(errs) |> Other }),
  // )
  // let _announce_req = io.debug(new_announce_request(info_enc))

  Ok(Nil)
}
