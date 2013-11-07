Gem::Specification.new do |s|
  s.name = "http_client"
  s.version = "0.5.0"
  s.date = "2013-11-07"
  s.summary = "HTTP client for JRuby"
  s.description = "This library wraps the Apache HTTPClient (4.3) in a simple fashion. The library is intended to be used in a multithreaded environment."
  s.platform = Gem::Platform::CURRENT
  s.requirements << "JRuby"
  s.requirements << "Java, since this library wraps a Java library"
  s.authors = ["Lukas Rieder"]
  s.email = "l.rieder@gmail.com"
  s.files = Dir["**/*"]
  s.homepage = "https://github.com/Overbryd/http_client"
  s.license = "MIT"
end
