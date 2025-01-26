import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/result

import bencode/bencode
import bencode/decode

pub type Error {
  DecodeError(bencode.DecodeError)
  InvalidFile(msg: String, causes: List(decode.DecodeError))
}

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

pub fn info_hash(info: TorrentInfo) -> String {
  let encoded = info_to_bencode(info) |> bencode.encode

  let info_hash =
    encoded
    |> crypto.hash(crypto.Sha1, _)
    // TODO: This is just for magnet links (which legacy used base32...), need to implement percent encoding
    |> bit_array.base16_encode

  info_hash
}

fn info_to_bencode(info: TorrentInfo) -> bencode.Value {
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

pub fn from_bits(bits: BitArray) -> Result(Torrent, Error) {
  use bencode <- result.try(
    bencode.decode(bits) |> result.map_error(DecodeError),
  )

  use torrent <- result.try(
    from_bencode(bencode)
    |> result.map_error(InvalidFile(msg: "parsing bencode", causes: _)),
  )

  Ok(torrent)
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

pub type FilePiece {
  FilePiece(path: List(String), byte_offset: Int, length: Int)
}

fn piece_map(
  piece_len: Int,
  piece_offset: Int,
  piece_num: Int,
  file_offset: Int,
  files: List(FileInfo),
  acc: List(#(List(String), Int, Int, Int)),
) -> List(#(List(String), Int, Int, Int)) {
  case files {
    [] -> acc
    [file, ..rest] -> {
      let bytes_in_piece = piece_len - piece_offset
      let next_offset = file_offset + bytes_in_piece

      case int.compare(next_offset, file.length) {
        // Piece ends at the end of this file
        order.Eq -> {
          let entry = #(file.path, piece_num, file_offset, bytes_in_piece)
          piece_map(piece_len, 0, piece_num + 1, 0, rest, [entry, ..acc])
        }

        // Piece ends in the middle of this file
        order.Lt -> {
          let entry = #(file.path, piece_num, file_offset, bytes_in_piece)
          piece_map(piece_len, 0, piece_num + 1, next_offset, files, [
            entry,
            ..acc
          ])
        }

        // Piece ends in next file
        order.Gt -> {
          let bytes_in_file = file.length - file_offset
          let new_piece_offset = piece_offset + bytes_in_file
          let entry = #(file.path, piece_num, file_offset, bytes_in_file)
          piece_map(piece_len, new_piece_offset, piece_num, 0, rest, [
            entry,
            ..acc
          ])
        }
      }
    }
  }
}

fn create_piece_map(
  piece_length: Int,
  pieces: List(BitArray),
  files: List(FileInfo),
) -> dict.Dict(Int, #(BitArray, List(FilePiece))) {
  let piece_hashes =
    list.index_map(pieces, fn(p, i) { #(i, p) }) |> dict.from_list

  piece_map(piece_length, 0, 0, 0, files, [])
  |> list.fold(dict.new(), fn(acc, p) {
    let #(path, piece_num, offset, length) = p
    let assert Ok(hash) = dict.get(piece_hashes, piece_num)
    let #(hash, prev) = dict.get(acc, piece_num) |> result.unwrap(#(hash, []))

    let piece_info = [FilePiece(path, offset, length), ..prev]
    dict.insert(acc, piece_num, #(hash, piece_info))
  })
}

pub fn get_piece_map(info: TorrentInfo) {
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
