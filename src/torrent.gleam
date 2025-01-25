import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/list
import gleam/string

import bencode/bencode
import bencode/decode

pub type FileInfo {
  FileInfo(path: String, length: Int)
}

pub type TorrentInfo {
  SingleFile(file: FileInfo, piece_length: Int, pieces: BitArray)
  MultiFile(
    dir_name: String,
    files: List(FileInfo),
    piece_length: Int,
    pieces: BitArray,
  )
}

fn file_info_to_bencode(file_info: FileInfo) -> bencode.Value {
  dict.from_list([
    #("length" |> bencode.String, file_info.length |> bencode.Int),
    #("path" |> bencode.String, file_info.path |> bencode.String),
  ])
  |> bencode.Dict
}

pub fn info_to_bencode(info: TorrentInfo) -> bencode.Value {
  case info {
    SingleFile(file, piece_length, pieces) -> {
      dict.from_list([
        #("name" |> bencode.String, file.path |> bencode.String),
        #("length" |> bencode.String, file.length |> bencode.Int),
        #("piece length" |> bencode.String, piece_length |> bencode.Int),
        #("pieces" |> bencode.String, pieces |> bencode.Bytes),
      ])
      |> bencode.Dict
    }
    MultiFile(dir_name, files, piece_length, pieces) -> {
      let files_list = list.map(files, file_info_to_bencode) |> bencode.List

      dict.from_list([
        #("name" |> bencode.String, dir_name |> bencode.String),
        #("files" |> bencode.String, files_list),
        #("piece length" |> bencode.String, piece_length |> bencode.Int),
        #("pieces" |> bencode.String, pieces |> bencode.Bytes),
      ])
      |> bencode.Dict
    }
  }
}

pub fn to_bencode(torrent: Torrent) -> bencode.Value {
  dict.from_list([
    #("announce" |> bencode.String, torrent.announce |> bencode.String),
    #(
      "announce-list" |> bencode.String,
      torrent.announce_list
        |> list.map(fn(inner) {
          list.map(inner, bencode.String) |> bencode.List
        })
        |> bencode.List,
    ),
    #("comment" |> bencode.String, torrent.comment |> bencode.String),
    #("created by" |> bencode.String, torrent.created_by |> bencode.String),
    #("creation date" |> bencode.String, torrent.creation_date |> bencode.Int),
    #("info" |> bencode.String, info_to_bencode(torrent.info)),
  ])
  |> bencode.Dict
}

pub type Torrent {
  Torrent(
    announce: String,
    announce_list: List(List(String)),
    comment: String,
    created_by: String,
    creation_date: Int,
    info: TorrentInfo,
  )
}

pub type AnnounceRequest {
  AnnounceRequest(
    info_hash: String,
    peer_id: String,
    port: Int,
    uploaded: Int,
    downloaded: Int,
    left: Int,
    compact: Int,
  )
}

pub fn new_announce_request(info: BitArray) -> AnnounceRequest {
  let info_hash =
    info
    |> crypto.hash(crypto.Sha1, _)
    |> bit_array.base64_url_encode(True)
    |> string.slice(0, 20)

  let peer_id =
    crypto.strong_random_bytes(32)
    |> bit_array.base64_url_encode(True)
    |> string.slice(0, 20)

  AnnounceRequest(
    info_hash:,
    peer_id:,
    port: 6881,
    uploaded: 0,
    downloaded: 0,
    left: 0,
    compact: 1,
  )
}

pub fn from_bencode(
  value: bencode.Value,
) -> Result(Torrent, List(decode.DecodeError)) {
  let decoder = {
    let info_decoder = {
      use piece_length <- decode.field("piece length", decode.int)
      use pieces <- decode.field("pieces", decode.bytes)

      let file_decoder = {
        use length <- decode.field("length", decode.int)
        use name <- decode.field("name", decode.string)
        decode.success(SingleFile(
          file: FileInfo(length:, path: name),
          piece_length:,
          pieces:,
        ))
      }

      let files_decoder = {
        let inner_file_decoder = {
          use length <- decode.field("length", decode.int)
          use name <- decode.field("path", decode.string)
          decode.success(FileInfo(path: name, length:))
        }

        use dir_name <- decode.field("name", decode.string)
        use files <- decode.field("files", decode.list(of: inner_file_decoder))
        decode.success(MultiFile(dir_name:, files:, piece_length:, pieces:))
      }

      decode.one_of(file_decoder, [files_decoder])
    }

    use announce <- decode.field("announce", decode.string)
    use announce_list <- decode.field(
      "announce-list",
      decode.list(of: decode.list(of: decode.string)),
    )
    use comment <- decode.field("comment", decode.string)
    use created_by <- decode.field("created by", decode.string)
    use creation_date <- decode.field("creation date", decode.int)
    use info <- decode.field("info", info_decoder)

    decode.success(Torrent(
      announce:,
      announce_list:,
      comment:,
      created_by:,
      creation_date:,
      info:,
    ))
  }

  decode.run(value, decoder)
}
