# encoding: UTF-8
$LOAD_PATH.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |s|
  s.name          = 'factor-connector-ssh'
  s.version       = '0.0.1'
  s.platform      = Gem::Platform::RUBY
  s.authors       = ['Maciej Skierkowski']
  s.email         = ['maciej@factor.io']
  s.homepage      = 'https://factor.io'
  s.summary       = 'SSH Factor.io Connector'
  s.files         = ['lib/factor/connector/ssh.rb']
  
  s.require_paths = ['lib']

  s.add_runtime_dependency 'net-sftp','2.1.2'
  s.add_runtime_dependency 'net-ssh','2.7.0'
  s.add_runtime_dependency 'net-scp','1.1.2'
  s.add_runtime_dependency 'sshkey','1.6.0'
  s.add_runtime_dependency 'factor-connector-api', '~> 0.0.1'
end