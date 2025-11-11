fx_version 'cerulean'
game 'gta5'

author 'R3Z_Dev'
description 'Ox_inv Refrigerator Script'
version '1.0.0'

shared_script 'config.lua'


client_scripts {
  'client/client.lua'
}

server_scripts {
  '@ox_lib/init.lua',
  '@ox_target/init.lua',
  'server/server.lua'
}

dependencies {
  'qb-core',
  'ox_lib',
  'ox_target'
}