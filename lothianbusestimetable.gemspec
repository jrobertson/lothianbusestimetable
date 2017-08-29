Gem::Specification.new do |s|
  s.name = 'lothianbusestimetable'
  s.version = '0.2.0'
  s.summary = 'Web scrapes a bus timetable from Lothian Buses website. #edinburgh #scotland'
  s.authors = ['James Robertson']
  s.files = Dir['lib/lothianbusestimetable.rb']
  s.add_runtime_dependency('nokorexi', '~> 0.3', '>=0.3.2')
  s.signing_key = '../privatekeys/lothianbusestimetable.pem'
  s.cert_chain  = ['gem-public_cert.pem']
  s.license = 'MIT'
  s.email = 'james@jamesrobertson.eu'
  s.homepage = 'https://github.com/jrobertson/lothianbusestimetable'
end
