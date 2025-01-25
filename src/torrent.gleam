import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/list
import gleam/string

import bencode/bencode
import bencode/decode

pub type FileInfo {
  FileInfo(path: List(String), length: Int)
}

pub type TorrentInfo {
  SingleFile(piece_length: Int, pieces: List(BitArray), file: FileInfo)
  MultiFile(
    piece_length: Int,
    pieces: List(BitArray),
    dir_name: String,
    files: List(FileInfo),
  )
}

fn multifile_info_to_bencode(file_info: FileInfo) -> bencode.Value {
  dict.from_list([
    #("length" |> bencode.String, file_info.length |> bencode.Int),
    #(
      "path" |> bencode.String,
      file_info.path |> list.map(bencode.String) |> bencode.List,
    ),
  ])
  |> bencode.Dict
}

fn collect_piece_hashes(
  flat_pieces: BitArray,
  acc: List(BitArray),
) -> Result(List(BitArray), String) {
  case flat_pieces {
    <<hash:bytes-size(20), rest:bytes>> ->
      collect_piece_hashes(rest, [hash, ..acc])
    <<>> -> Ok(acc |> list.reverse)
    _ ->
      Error(
        "last piece was "
        <> bit_array.byte_size(flat_pieces) |> int.to_string
        <> " bytes, expected pieces to be 20-byte aligned",
      )
  }
}

pub fn info_to_bencode(info: TorrentInfo) -> bencode.Value {
  let flat_pieces = info.pieces |> list.fold(<<>>, bit_array.append)
  case info {
    SingleFile(piece_length, _pieces, file) -> {
      let assert [name] = file.path

      dict.from_list([
        #("name" |> bencode.String, name |> bencode.String),
        #("length" |> bencode.String, file.length |> bencode.Int),
        #("piece length" |> bencode.String, piece_length |> bencode.Int),
        #("pieces" |> bencode.String, flat_pieces |> bencode.Bytes),
      ])
    }
    MultiFile(piece_length, _pieces, dir_name, files) -> {
      let files_list =
        list.map(files, multifile_info_to_bencode) |> bencode.List

      dict.from_list([
        #("name" |> bencode.String, dir_name |> bencode.String),
        #("files" |> bencode.String, files_list),
        #("piece length" |> bencode.String, piece_length |> bencode.Int),
        #("pieces" |> bencode.String, flat_pieces |> bencode.Bytes),
      ])
    }
  }
  |> bencode.Dict
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

pub fn new_announce_request(torrent_info: TorrentInfo) -> AnnounceRequest {
  let encoded = info_to_bencode(torrent_info) |> bencode.encode
  let info_hash =
    encoded
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

pub type Piece {
  Piece(path: List(String), hash: BitArray, byte_offset: Int, length: Int)
}

fn file_pieces(
  piece_hashes piece_hashes: dict.Dict(Int, BitArray),
  piece_length piece_length: Int,
  path path: List(String),
  length length: Int,
  file_piece_index file_piece_index: Int,
  piece_index piece_index: Int,
  acc acc: List(Piece),
) -> List(Piece) {
  case length > piece_length {
    True -> {
      let assert Ok(hash) = dict.get(piece_hashes, piece_index)

      let piece =
        Piece(
          path:,
          hash:,
          byte_offset: file_piece_index * piece_length,
          length: piece_length,
        )
      file_pieces(
        piece_hashes:,
        piece_length:,
        path:,
        length: length - piece_length,
        file_piece_index: file_piece_index + 1,
        piece_index: piece_index + 1,
        acc: [piece, ..acc],
      )
    }
    False -> {
      // Last piece of this file
      let assert Ok(hash) = dict.get(piece_hashes, piece_index)

      let piece =
        Piece(
          path:,
          hash:,
          byte_offset: file_piece_index * piece_length,
          length:,
        )
      [piece, ..acc]
    }
  }
}

fn create_piece_map(
  piece_length: Int,
  pieces: List(BitArray),
  files: List(FileInfo),
) -> dict.Dict(Int, Piece) {
  let piece_hashes =
    list.index_map(pieces, fn(p, i) { #(i, p) }) |> dict.from_list

  let pieces =
    list.fold(files, [], fn(acc, file) {
      file_pieces(
        piece_hashes:,
        piece_length:,
        path: file.path,
        length: file.length,
        file_piece_index: 0,
        piece_index: acc |> list.length,
        acc:,
      )
    })
    |> list.reverse
    |> list.index_map(fn(p, i) { #(i, p) })

  dict.from_list(pieces)
}

pub fn piece_map(info: TorrentInfo) {
  case info {
    SingleFile(piece_length, pieces, file) ->
      create_piece_map(piece_length, pieces, [file])
    MultiFile(piece_length, pieces, _dir_name, files) ->
      create_piece_map(piece_length, pieces, files)
  }
}

pub fn from_bencode(
  value: bencode.Value,
) -> Result(Torrent, List(decode.DecodeError)) {
  let decoder = {
    let info_decoder = {
      use piece_length <- decode.field("piece length", decode.int)
      let pieces_decoder = {
        use flat_pieces <- decode.field("pieces", decode.bytes)
        case collect_piece_hashes(flat_pieces, []) {
          Ok(pieces) -> decode.success(pieces)
          Error(err) -> decode.failure([], err)
        }
      }

      use pieces <- decode.then(pieces_decoder)

      let file_decoder = {
        use length <- decode.field("length", decode.int)
        use name <- decode.field("name", decode.string)
        decode.success(SingleFile(
          file: FileInfo(length:, path: [name]),
          piece_length:,
          pieces:,
        ))
      }

      let files_decoder = {
        let inner_file_decoder = {
          use length <- decode.field("length", decode.int)
          use path <- decode.field("path", decode.list(decode.string))
          decode.success(FileInfo(path:, length:))
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
