package com.hackdiary.replies

import scala.collection.JavaConversions._

import java.util.concurrent.TimeUnit._

import com.ning.http.client._
import org.codehaus.jackson.map._
import org.codehaus.jackson._
import com.codahale.jerkson.Json._

import com.yammer.metrics.Instrumented
import java.util.concurrent.TimeUnit
import com.yammer.metrics.reporting.ConsoleReporter

import redis.clients.jedis._

import akka.actor._
import akka.event._
import akka.routing._
import akka.config._
import akka.config.Supervision._

case class Poll()
case class Start()
case class InterestedInUsers(users: List[String])
case class Response(params: Map[String, String], response: com.ning.http.client.Response)
case class Tweet(tweet: JsonNode)
case class Publish(channel: String, data: String)
case class ControlMessage(message: String)
case class NewUser(token: String)

object Monitor extends App {
  val jedispool = new JedisPool(new JedisPoolConfig(), "localhost")

  val monitor = Actor.actorOf[Monitor].start

  val factory = SupervisorFactory(
    SupervisorConfig(
      OneForOneStrategy(List(classOf[Exception]), 3, 10),
      Supervise(monitor, Permanent) ::
        Nil))

  factory.newInstance.start
  monitor ! Start
  Actor.spawn {
    val jedis = jedispool.getResource
    try {
      jedis.subscribe(new JedisPubSub {
        def onMessage(channel: String, message: String) = monitor ! ControlMessage(message)
        def onPMessage(string: String, string1: String, string2: String) = {}
        def onSubscribe(string: String, i: Int) = {}
        def onUnsubscribe(string: String, i: Int) = {}
        def onPUnsubscribe(string: String, i: Int) = {}
        def onPSubscribe(string: String, i: Int) = {}
      }, "or:commands")
    } finally {
      jedispool.returnResource(jedis)
    }
  }
  //ConsoleReporter.enable(10, TimeUnit.SECONDS)
}

class Monitor extends Actor {
  val mapper = new ObjectMapper

  def receive = {
    case Start => {
      for (token <- User.unwrapped_redis(_.smembers("or:users"))) self ! NewUser(token)
      become(ready(Map.empty, Set.empty))
    }
  }

  def ready(registry: Map[String, Set[UntypedChannel]], tokens: Set[String]): Receive = {
    case NewUser(token) => {
      if (!tokens.contains(token)) {
        val actor = Actor.actorOf(new User(self, token)).start
        self.link(actor)
        Scheduler.schedule(actor, Poll, (math.random * 12).toInt, 12, SECONDS)
        become(ready(registry, tokens + token))
      }
    }
    case ControlMessage(message) => control(message)
    case InterestedInUsers(users) => {
      val newRegistry = registry ++ users.map { id =>
        (id -> (registry.getOrElse(id, Set.empty) + self.channel))
      }
      become(ready(newRegistry, tokens))
    }
    case Tweet(tweet) => {
      if (!(tweet path "in_reply_to_user_id" isNull)) {
        val user_id = tweet.path("user").path("id_str").getTextValue
        for (user <- registry.getOrElse(user_id, Set.empty)) user ! Tweet(tweet)
      }
    }
    case Publish(channel, data) => User.unwrapped_redis(_.publish("juggernaut", generate(Map("channels" -> List("/tweets/" + channel), "data" -> data))))
  }

  def control(message: String) = {
    try {
      val control = mapper.readTree(message)
      control path "command" getTextValue match {
        case "checkin" => EventHandler.info(this, "User %s checked in.".format(control path "token" getTextValue))
        case "setup" => {
          val token = control.path("token").getTextValue
          EventHandler.info(this, "New user %s.".format(token))
          self ! NewUser(token)
        }
        case other => EventHandler.warning(this, "Unhandled command: %s".format(control))
      }
    } catch {
      case e: Exception => EventHandler.warning(this, "Control message not parseable: %s".format(message))
    }
  }
}
