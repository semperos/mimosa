path = require 'path'
fs = require 'fs'

_ = require 'lodash'

logger = require '../logger'

module.exports = class RequireRegister

  depsRegistry: {}
  aliasFiles: {}
  aliasDirectories: {}
  requireFiles: []
  tree: {}
  mappings: {}
  shims: {}

  requireStringRegex: /[^.]\s*require\s*\(\s*["']([^'"\s]+)["']\s*\)/g
  commentRegExp: /(\/\*([\s\S]*?)\*\/|([^:]|^)\/\/(.*)$)/mg

  setConfig: (@config) ->
    @verify = @config.require.verify.enabled
    unless @rootJavaScriptDir?
      @rootJavaScriptDir = if config.virgin
        path.join @config.watch.sourceDir, @config.watch.javascriptDir
      else
        path.join @config.watch.compiledDir, @config.watch.javascriptDir
      logger.debug "Root Javascript directory set at [[ #{@rootJavaScriptDir} ]]"

  process: (fileName, source) ->
    require = @_require(fileName)
    define = @_define(fileName)
    define.amd = {jquery:true}
    require.config = require
    requirejs = require
    requirejs.config = require
    # pretend this isn't node
    exports = undefined
    @_requirejs(requirejs)
    try
      eval(source)
    catch e
      @_logger "File named [#{fileName}] is not wrapped in a 'require' or 'define' function call.", "warn"
      @_logger "#{e}", 'warn'

  remove: (fileName) ->
    delete @depsRegistry[fileName] if @depsRegistry[fileName]?
    @_deleteForFileName(fileName, @aliasFiles)
    @_deleteForFileName(fileName, @aliasDirectories)
    @_verifyAll()

  startupDone: (@startupComplete = true) ->
    return if @startupAlreadyDone
    logger.debug "***Require registration has learned that startup has completed, verifying require registrations***"
    @startupAlreadyDone = true
    @_verifyAll()

  treeBases: ->
    Object.keys(@tree)

  treeBasesForFile: (fileName) ->
    return [fileName] if @requireFiles.indexOf(fileName) >= 0

    bases = []
    for base, deps of @tree
      bases.push(base) if deps.indexOf(fileName) >= 0

    logger.debug "Dependency tree bases for file [[ #{fileName} ]] are: #{bases.join('\n')}"

    bases

  # determine if an alias exists for a given path
  aliasForPath: (filePath) ->
    for main, paths of @aliasFiles
      for alias, dep of paths
        if dep is filePath or dep is path.join @rootJavaScriptDir, "#{filePath}.js"
          return alias

  ###
  Private
  ###

  _logger: (message, method = 'error') ->
    if @verify
      logger[method](message)
    else
      logger.debug message

  _require: (fileName) ->
    (deps, callback, errback, optional) =>
      [deps, config] = @_requireOverride(deps, callback, errback, optional)
      logger.debug "Inside require function call for [[ #{fileName} ]], file has depedencies of:\n#{deps}"

      if config
        logger.debug "[[ #{fileName} ]] has require configuration inside of it:\n#{JSON.stringify(config, null, 2)}"
        @requireFiles.push fileName
        @_handleConfigPaths(fileName, config.map ? null, config.paths ? null)
        @_handleShims(fileName, config.shim ? null)
      @_handleDeps(fileName, deps)

  _define: (fileName) ->
    (id, deps, funct) =>
      deps = @_defineOverride(id, deps, funct)
      logger.debug "Inside define block for [[ #{fileName} ]], found dependencies:\n#{deps}"
      @_handleDeps(fileName, deps)

  # may not be necessary, but for future reference
  _requirejs: (r) ->
    r.version = ''
    r.onError = ->
    r.jsExtRegExp = /^\/|:|\?|\.js$/
    r.isBrowser = true
    r.load = ->
    r.exec = ->
    r.toUrl = -> ""
    r.undef = ->
    r.defined = ->
    r.specified = ->

  _deleteForFileName: (fileName, aliases) ->
    logger.debug "Deleting aliases for file name [[ #{fileName} ]]"
    logger.debug "Aliases before delete:\n#{JSON.stringify(aliases, null, 2)}\n"

    delete aliases[fileName] if aliases[fileName]
    for fileName, paths of aliases
      for alias, aliasPath of paths
        delete paths[alias] if aliasPath is fileName

    logger.debug "Aliases after delete:\n#{JSON.stringify(aliases, null, 2)}\n"

  _verifyAll: ->
    @_verifyConfigForFile(file)  for file in @requireFiles
    @_verifyFileDeps(file, deps) for file, deps of @depsRegistry
    @_verifyShims(file, shims) for file, shims of @shims
    @_buildTree() unless @config.virgin

  _handleShims: (fileName, shims) ->
    if @startupComplete
      @_verifyShims(fileName, shims)
    else
      @shims[fileName] = shims

  _verifyShims: (fileName, shims) ->
    unless shims?
      return logger.debug "No shims"

    for name, config of shims
      logger.debug "Processing shim [[ #{name} ]] with config of [[ #{JSON.stringify(config)} ]]"
      unless @_fileExists(@_resolvePath(fileName, name))
        alias = @_findAlias(name, @aliasFiles)
        unless alias
          @_logger "Shim path [[ #{name} ]] inside file [[ #{fileName} ]] cannot be found."

      deps = if Array.isArray(config) then config else config.deps
      if deps?
        for dep in deps
          logger.debug "Resolving shim dependency [[ #{dep} ]]"
          unless @_fileExists(@_resolvePath(fileName, dep))
            alias = @_findAlias(dep, @aliasFiles)
            unless alias
              @_logger "Shim [[ #{name} ]] inside file [[ #{fileName} ]] refers to a dependency that cannot be found [[ #{dep} ]]."
      else
        logger.debug "No 'deps' found for shim"

  _buildTree: ->
    for f in @requireFiles
      logger.debug "Building tree for require file [[ #{f} ]]"
      @tree[f] = []
      @_addDepsToTree(f, f, f)
      logger.debug "Full tree for require file [[ #{f} ]] is:\n#{JSON.stringify(@tree[f], null, f)}"

  _addDepsToTree: (f, dep, origDep) ->
    unless @depsRegistry[dep]?
      return logger.debug "Dependency registry has no depedencies for [[ #{dep} ]]"

    for aDep in @depsRegistry[dep]
      exists = @_fileExists aDep

      unless exists
        logger.debug "Cannot find dependency [[ #{aDep} ]] for file [[ #{dep} ]], checking aliases/paths/maps"
        aDep = @_findAlias(aDep, @aliasFiles)

        unless aDep?
          return logger.debug "Cannot find dependency [[ #{aDep} ]] in aliases, is likely bad path"

        if aDep.indexOf('MAPPED!') >= 0
          aDep = @_findMappedDependency(dep, aDep)
          logger.debug "Dependency found in mappings [[ #{aDep} ]]"


      logger.debug "Resolved depencency for file [[ #{dep} ]] to [[ #{aDep} ]]"

      if @tree[f].indexOf(aDep) < 0
        logger.debug "Adding dependency [[ #{aDep} ]] to the tree"
        @tree[f].push(aDep)
      else
        logger.debug "Dependency [[ #{aDep} ]] already in the tree, skipping"

      if aDep isnt origDep
        @_addDepsToTree(f, aDep, dep)
      else
        logger.debug "[[ #{aDep} ]] may introduce a circular dependency"


  _handleConfigPaths: (fileName, maps, paths) ->
    if @startupComplete
      @_verifyConfigForFile(fileName, maps, paths)
      # remove the dependencies for the config file as
      # they'll get checked after the config paths are checked in
      @depsRegistry[fileName] = []
      @_verifyFileDeps(file, deps) for file, deps of @depsRegistry
    else
      @aliasFiles[fileName] = paths
      @mappings[fileName] = maps

  _handleDeps: (fileName, deps) ->
    if @startupComplete
      @_verifyFileDeps(fileName, deps)
      @_buildTree() unless @config.virgin
    else
      @depsRegistry[fileName] = deps

  _verifyConfigForFile: (fileName, maps, paths) ->
    # if nothing passed in, then is verify all
    maps = maps ? @mappings[fileName]
    paths = if paths
      paths
    else
      paths = {}
      paths = _.extend(paths, @aliasFiles[fileName])       if @aliasFiles[fileName]?
      paths = _.extend(paths, @aliasDirectories[fileName]) if @aliasDirectories[fileName]?
      paths

    @aliasFiles[fileName] = {}
    @aliasDirectories[fileName] = {}
    @_verifyConfigPath(fileName, alias, aliasPath) for alias, aliasPath of paths
    @_verifyConfigMappings(fileName, maps)

  _verifyConfigMappings: (fileName, maps) ->
    logger.debug "Verifying [[ #{fileName} ]] maps:\n#{JSON.stringify(maps, null, 2)}"
    # rewrite module paths to full paths
    for module, mappings of maps
      if module isnt '*'
        fullDepPath = @_resolvePath(fileName, module)
        exists = @_fileExists fullDepPath
        if exists
          logger.debug "Verified path for module [[ #{module} ]] at [[ #{fullDepPath} ]]"
          delete maps[module]
          maps[fullDepPath] = mappings
        else
          @_logger "Mapping inside file [[ #{fileName} ]], refers to module that cannot be found [[ #{module} ]]."
          continue
      else
        logger.debug "Not going to verify path for '*'"

    for module, mappings of maps
      for alias, aliasPath of mappings
        fullDepPath = @_resolvePath(fileName, aliasPath)
        if fullDepPath.indexOf('http') is 0
          logger.debug "Web path [[ #{fullDepPath} ]] for alias [[ #{alias} ]]being accepted"
          @aliasFiles[fileName][alias] = "MAPPED!#{alias}"
          continue

        exists = @_fileExists fullDepPath
        unless exists
          alias = @_findAlias(aliasPath, @aliasFiles)
          if alias then exists = true

        if exists
          logger.debug "Found mapped dependency [[ #{alias} ]] at [[ #{fullDepPath} ]]"
          @aliasFiles[fileName][alias] = "MAPPED!#{alias}"
          maps[module][alias] = fullDepPath
        else
          @_logger "Mapping inside file [[ #{fileName} ]], for module [[ #{module} ]] has path that cannot be found [[ #{aliasPath} ]]."

  _verifyConfigPath: (fileName, alias, aliasPath) ->
    logger.debug "Verifying configPath in fileName [[ #{fileName} ]], path alias [[ #{alias} ]], with aliasPath(s) of [[ #{aliasPath} ]]"
    if Array.isArray(aliasPath)
      logger.debug "Paths are in array"
      for aPath in aliasPath
        @_verifyConfigPath(fileName, alias, aPath)
      return

    # mapped paths are ok
    if aliasPath.indexOf("MAPPED") is 0
      return logger.debug "Is mapped path [[ #{aliasPath} ]]"

    # as are web resources, CDN, etc
    if aliasPath.indexOf('http') is 0
      logger.debug "Is web resource path [[ #{aliasPath} ]]"
      return @aliasFiles[fileName][alias] = aliasPath

    fullDepPath = @_resolvePath(fileName, aliasPath)

    exists = @_fileExists fullDepPath
    if exists
      if fs.statSync(fullDepPath).isDirectory()
        logger.debug "Path found at [[ #{fullDepPath}]], is a directory, adding to list of alias directories"
        @aliasDirectories[fileName][alias] = fullDepPath
      else
        logger.debug "Path found at [[ #{fullDepPath}]], is a file, adding to list of alias files"
        @aliasFiles[fileName][alias] = fullDepPath
    else
      pathAsDirectory = fullDepPath.replace(/.js$/, '')
      if @_fileExists pathAsDirectory
        logger.debug "Path exists as directory, [[ #{pathAsDirectory} ]], adding to list of alias directories"
        @aliasDirectories[fileName] ?= {}
        @aliasDirectories[fileName][alias] = pathAsDirectory
      else
        @_logger "Dependency [[ #{aliasPath} ]] for path alias [[ #{alias} ]], inside file [[ #{fileName} ]], cannot be found."
        logger.debug "Used this as full dependency path [[ #{fullDepPath} ]]"

  _verifyFileDeps: (fileName, deps) ->
    @depsRegistry[fileName] = []
    return unless deps?
    @_verifyDep(fileName, dep) for dep in deps

  _verifyDep: (fileName, dep) ->
    # require, module = valid dependencies passed by require
    if dep is 'require' or dep is 'module' or dep is 'exports'
      return logger.debug "Encountered keyword-esque dependency [[ #{dep} ]], ignoring."

    # as are web resources, CDN, etc
    if dep.indexOf('http') is 0
      logger.debug "Is web resource dependency [[ #{dep} ]], no further checking required"
      return @_registerDependency(fileName, dep)

    # handle plugins
    if dep.indexOf('!') >= 0
      [plugin, dep] = dep.split('!')
      logger.debug "Is plugin dependency, going to verify both plugin path [[ #{plugin}]] and dependency after '!', [[ #{dep} ]] "
      @_verifyDep(fileName, plugin)
      plugin = true

    # resolve path, if mapped, find already calculated map path
    fullDepPath = if dep.indexOf('MAPPED') is 0
      logger.debug "Is mapped dependency, looking in mappings..."
      @_findMappedDependency(fileName, dep)
    else
      @_resolvePath(fileName, dep, plugin)

    exists = @_fileExists fullDepPath
    if exists
      # file exists, register it
      @_registerDependency(fileName, fullDepPath)
    else
      logger.debug "Cannot find dependency [[ #{fullDepPath} ]], looking in paths..."
      alias = @_findAlias(dep, @aliasFiles)
      if alias
        # file does not exist, but is aliased, register the alias
        @_registerDependency(fileName, dep)
      else
        logger.debug "Cannot find dependency as path alias..."
        pathWithDirReplaced = @_findPathWhenAliasDiectory(dep)
        if pathWithDirReplaced? and @_fileExists pathWithDirReplaced
          # file does not exist, but can be found by following directory alias
          @_registerDependency(fileName, pathWithDirReplaced)
        else
          @_logger "Dependency [[ #{dep} ]], inside file [[ #{fileName} ]], cannot be found."
          logger.debug "Used this as full dependency path [[ #{fullDepPath} ]]"
          @_registerDependency(fileName, dep)
          # much sadness, cannot find the dependency

  _findMappedDependency: (fileName, dep) ->
    depName = dep.split('!')[1]

    for mainFile, mappings of @mappings
      return mappings[fileName][depName] if mappings[fileName]?[depName]?

    for mainFile, mappings of @mappings
      return mappings['*'][depName] if mappings['*']?[depName]?

    @_logger "Mimosa has a bug! Ack! Cannot find mapping and it really should have."

  _registerDependency: (fileName, dependency) ->
    logger.debug "Found dependency [[ #{dependency} ]] for file name [[ #{fileName} ]], registering it!"
    @depsRegistry[fileName].push(dependency)
    if @_isCircular(fileName, dependency)
      @_logger "A circular dependency exists between [[ #{fileName} ]] and [[ #{dependency} ]]", 'warn'

  _isCircular: (dep1, dep2) ->
    oneHasTwo = @depsRegistry[dep1]?.indexOf(dep2) >= 0
    twoHasOne = @depsRegistry[dep2]?.indexOf(dep1) >= 0
    oneHasTwo and twoHasOne

  _findAlias: (dep, aliases) ->
    for fileName, paths of aliases
      if paths[dep]?
        logger.debug "Found alias [[ #{paths[dep]} ]] in file name [[ #{fileName} ]] for dependency [[ #{dep} ]]"
        return paths[dep]

  _resolvePath: (fileName, dep, plugin = false) ->
    if dep.indexOf(@rootJavaScriptDir) is 0
      return dep

    # handle windows paths by splitting and rejoining
    dep = dep.split('/').join(path.sep)

    fullPath = if dep.charAt(0) is '.'
      path.resolve path.dirname(fileName), dep
    else
      path.join @rootJavaScriptDir, dep

    if fullPath.match(/\.\w+$/) and plugin
      logger.debug "Encountered plugin file with extension, letting that pass as is [[ fullPath ]]"
      fullPath
    else
      "#{fullPath}.js"

  _findPathWhenAliasDiectory: (dep) ->
    pathPieces = dep.split('/')
    alias = @_findAlias(pathPieces[0], @aliasDirectories)
    if alias
      logger.debug "Found alias as directory [[ #{alias} ]]"
      pathPieces[0] = alias
      fullPath = pathPieces.join(path.sep)
      "#{path.normalize(fullPath)}.js"
    else
      null

  _defineOverride: (name, deps, callback) ->
    if typeof name isnt 'string'
      callback = deps
      deps = name

    if !Array.isArray(deps)
      callback = deps
      deps = []

    if !deps.length and _.isFunction(callback)
      if (callback.length)
        callback.toString()
          .replace(@commentRegExp, '')
          .replace @requireStringRegex, (match, dep) ->
            deps.push(dep)

    deps

  _requireOverride: (deps, callback, errback, optional) ->
    if !Array.isArray(deps) and typeof deps isnt 'string'
      config = deps
      if Array.isArray(callback)
        deps = callback
        callback = errback
      else
        deps = []

    if !Array.isArray(deps)
      logger.warn "Not validating dependencies [[ #{deps} ]]. 'require' dependencies not set correctly. Dependencies should be an array."
      deps = []

    [deps, config]

  _fileExists: (filePath) ->
    return true if fs.existsSync filePath
    if @config.virgin
      # templates is fine, will never be written, doesn't actually exist unless it is written
      return true if filePath is path.join(@rootJavaScriptDir, "templates.js")

      logger.debug "Is virgin, need to try a bit harder to find file in source directories using extensions [[ #{@config.javascriptExtensions} ]]"
      for extension in @config.javascriptExtensions
        filePath = filePath.replace(/\.[^.]+$/, ".#{extension}")
        return true if fs.existsSync filePath

    false

module.exports = new RequireRegister()