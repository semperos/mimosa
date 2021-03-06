path =   require 'path'
fs =     require 'fs'

logger = require '../util/logger'

copyConfig = (opts) ->
  if opts.debug then logger.setDebug()
  configPath = path.join __dirname, '..', 'skeleton', "mimosa-config.coffee"
  configFileContents = fs.readFileSync(configPath)
  currPath = path.join path.resolve(''), "mimosa-config.coffee"
  logger.debug "Writing config file to #{currPath}"
  fs.writeFile currPath, configFileContents, 'ascii'
  logger.success "Copied default config file into current directory."

register = (program, callback) ->
  program
    .command('config')
    .option("-D, --debug", "run in debug mode")
    .description("copy the default Mimosa config into the current folder")
    .action(callback)
    .on '--help', =>
      logger.green('  The config command will copy the default Mimosa config to the current directory.')
      logger.green('  There are no options for the config command.')
      logger.blue( '\n    $ mimosa config\n')

module.exports = (program) ->
  register(program, copyConfig)