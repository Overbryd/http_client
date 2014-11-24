# A simple yet powerful HTTP client for JRuby

This library wraps the Apache HttpClient (4.3) in a simple fashion.
It currently implements all common HTTP verbs, connection pooling, retries and transparent gzip response handling. All common exceptions from Javaland are wrapped as Ruby exceptions. The library is intended to be used in a multithreaded environment.

It is currently in use in some of my production environments, including one that frequently talks to Facebook. I could not find a single issue since 2013.

## Examples

#### A simple GET request

```ruby
require "http_client"

client = HttpClient.new
response = client.get("http://www.google.com/robots.txt")

response.status
# => 200

response.body
# =>
# User-agent: *
# ...
```

#### POST a form

```ruby
response = client.post("http://geocities.com/darrensden/guestbook",
  :form => {
    :name => "Joe Stub",
    :email => "joey@ymail.com",
    :comment => "Hey, I really like your site! Awesome stuff"
  }
)
```

#### POST JSON data

```ruby
response = client.post("http://webtwoopointo.com/v1/api/guestbooks/123/comments",
  :json => {
    :name => "Jason",
    :email => "jason@gmail.com",
    :comment => "Your site is great!"
  }
)
```

#### Provide request headers

```ruby
response = client.get("http://secretservice.com/users/123",
  :headers => { "X-Auth": "deadbeef23" }
)
```

#### Using a connection pool

Rather than opening a new connection each and every time, you can pool connections to your target host. Using `:use_connection_pool => true` gives you fine grained control over the total number of connections and the number of connections your client will maintain to each route.

```ruby
$client = HttpClient.new(
  :use_connection_pool => true,
  :max_connections => 3,
  :max_connections_per_route => 1
)

%[www.google.de www.yahoo.com www.altavista.com].each do |host|
  Thread.new do
    response = $client.get("http://#{host}/robots.txt")
    puts response.body
  end
end
```

##### Connection pool cleanup

**tl;dr This library does this by default.** 
In case you do not want _one extra thread_ cleaning after all `HttpClient` instances that use connection pooling, you can set the option `:use_connection_cleaner => false` and call `HttpClient#cleanup_connections` manually.
The background on this is, that you should actively expire your idle connections from the client side. Doing so will prevent you from ending up with too many `CLOSE-WAIT` connections. There are servers that never close the connection from their side, leaving the task up to the client.

## Contribute

This library covers just what I need. I wanted to have a thread safe HTTP client that supports a fixed connection pool with fine grained connection and timeout configurations.

Before you start hacking away, [have a look at the issues](https://github.com/Overbryd/http_client/issues). There might be stuff that is already in the making. If so, there will be a published branch you can contribute to.

Just create a fork and send me a pull request. I would be honored to look at your input.

[![Build Status](https://travis-ci.org/Overbryd/http_client.png)](https://travis-ci.org/Overbryd/http_client)

## Legal

Copyright by Lukas Rieder, 2013, Licensed under the MIT License, see LICENSE
