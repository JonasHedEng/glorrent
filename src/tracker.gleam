// import torrent
// import torrent_table

// fn build_request(url, event, torrent, info_hash, peer_id, port) {
//   // let torrent = torrent_table.handle_message()
//   let query =
//     torrent.AnnounceRequest(
//       info_hash: info_hash,
//       peer_id: peer_id,
//       uploaded: torrent.uploaded,
//       downloaded: torrent.downloaded,
//       left: torrent.left,
//       port: port,
//       compact: 1,
//     )

//   let query =
//     query
//     |> add_tracker_id(url)
//     |> add_event(event)
//     |> uri.percent_encode

//   url <> "?" <> query
// }

// pub type AnnounceRequest {
//   AnnounceRequest(
//     info_hash: String,
//     peer_id: String,
//     port: Int,
//     uploaded: Int,
//     downloaded: Int,
//     left: Int,
//     compact: Int,
//   )
// }

// pub fn new_announce_request(
//   torrent_info: torrent.TorrentInfo,
// ) -> AnnounceRequest {
//   let encoded = info_to_bencode(torrent_info) |> bencode.encode
//   let info_hash =
//     encoded
//     |> crypto.hash(crypto.Sha1, _)
//     |> bit_array.base64_url_encode(True)
//     |> string.slice(0, 20)

//   let peer_id =
//     crypto.strong_random_bytes(32)
//     |> bit_array.base64_url_encode(True)
//     |> string.slice(0, 20)

//   AnnounceRequest(
//     info_hash:,
//     peer_id:,
//     port: 6881,
//     uploaded: 0,
//     downloaded: 0,
//     left: 0,
//     compact: 1,
//   )
// }
