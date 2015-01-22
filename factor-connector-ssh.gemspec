# encoding: UTF-8
$LOAD_PATH.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |s|
  s.name          = 'factor-connector-ssh'
  s.version       = '0.0.6'
  s.platform      = Gem::Platform::RUBY
  s.authors       = ['Maciej Skierkowski']
  s.email         = ['maciej@factor.io']
  s.homepage      = 'https://factor.io'
  s.summary       = 'SSH Factor.io Connector'
  s.files         = ['lib/factor/connector/ssh.rb']
  
  s.require_paths = ['lib']

  s.add_runtime_dependency 'net-ssh','~> 2.9.2'
  s.add_runtime_dependency 'net-scp','~> 1.2.1'
  s.add_runtime_dependency 'factor-connector-api', '~> 0.0.14'

  s.add_development_dependency 'codeclimate-test-reporter', '~> 0.4.5'
  s.add_development_dependency 'rspec', '~> 3.1.0'
  s.add_development_dependency 'rake', '~> 10.4.2'
end