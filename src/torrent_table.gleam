import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

import torrent.{type Torrent}

pub type Message {
  Shutdown
  Add(torrent: Torrent, reply_with: Subject(String))
  Get(hash: String, reply_with: Subject(Result(Torrent, Nil)))
}

pub fn handle_message(
  message: Message,
  table: Dict(String, Torrent),
) -> actor.Next(Message, Dict(String, Torrent)) {
  case message {
    Shutdown -> actor.Stop(process.Normal)

    Add(torrent, client) -> {
      let hash = torrent.info_hash(torrent.info)
      let new_table = dict.insert(table, hash, torrent)

      process.send(client, hash)
      actor.continue(new_table)
    }

    Get(hash, client) -> {
      process.send(client, dict.get(table, hash))
      actor.continue(table)
    }
  }
}
