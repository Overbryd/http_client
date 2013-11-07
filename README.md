# A simple yet powerful HTTP client for JRuby

This library wraps the Apache HttpClient (4.3) in a simple fashion.
It currently implements all common HTTP verbs, connection pooling, retries and transparent gzip response handling. All common exceptions from Javaland are wrapped as Ruby exceptions. The library is intended to be used in a multithreaded environment.

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
    :email => "jaz0r@gmail.com",
    :comment => "Yo dawg, luv ur site!"
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

```ruby
$client = HttpClient.new(
  :use_connection_pool => true,
  :max_connections => 10,
)

%[www.google.de www.yahoo.com www.altavista.com].each do |host|
  Thread.new do
    response = $client.get("http://#{host}/robots.txt")
    puts response.body
  end
end
```

## Contribute

This library covers just what I need. I wanted to have a thread safe HTTP client that has a fixed connection pool with fine grained timeout configurations.

Before you start hacking away, [have a look at the issues](https://github.com/Overbryd/http_client/issues). There might be stuff that is already in the making. If so, there will be a published branch you can contribute to.

Just create a fork and send me a pull request. I would be honored to look at your input.

## Legal

Copyright by Lukas Rieder, 2013, Licensed under the MIT License, see LICENSE
