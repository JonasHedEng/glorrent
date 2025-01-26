import bencode/bencode
import gleam/dict
import gleam/erlang/process
import gleam/io
import gleam/otp/actor

import simplifile

import torrent
import torrent_table

pub fn main() {
  let path = "./example-torrents/tears-of-steel.torrent"
  let assert Ok(content) = simplifile.read_bits(path)
  let assert Ok(torrent) = torrent.from_bits(content)

  // Start TorrentTable actor
  let assert Ok(torrent_table_actor) =
    actor.start(dict.new(), torrent_table.handle_message)

  let hash =
    process.call(torrent_table_actor, torrent_table.Add(torrent, _), 100)

  io.println(hash)

  let assert Ok(stored_torrent) =
    process.call(torrent_table_actor, torrent_table.Get(hash, _), 10)

  io.println(stored_torrent |> torrent.to_bencode |> bencode.pretty_format)

  // torrent
  // |> bencode.pretty_format
  // |> result.unwrap("")
  // |> io.println

  // use torrent <- result.try(parse_torrent_file(path))

  // let enc_torr =
  //   torrent
  //   |> torrent.to_bencode
  // let _ =
  //   simplifile.write_bits(
  //     path <> ".clone",
  //     enc_torr
  //       |> bencode.encode,
  //   )

  // io.println(enc_torr |> bencode.pretty_format)

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
