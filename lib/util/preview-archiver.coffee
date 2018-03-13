Configuration = require './configuration'
scrape = require 'website-scraper'
zipper = require 'zip-folder'
moment = require 'moment'
q = require 'q'
path = require 'path'
rimraf = require 'rimraf'

class PreviewArchiver

  constructor: () ->
    @configuration = new Configuration()

  zipFolder: (folder, destination) ->
    deferred = q.defer()
    zipper folder, destination, (err) ->
      if err
        console.error err
        deferred.reject err
      else
        deferred.resolve destination

    return deferred.promise

  deleteFolder: (folder) ->
    deferred = q.defer()

    rimraf folder, (err) ->
      if err
        deferred.reject err
      else
        deferred.resolve true

    return deferred.promise

  now: () ->
    return moment().format("YYYYMMDD_HHmmss")

  extractName: (url) ->
    [..., lastPath] = url.split("/")
    return lastPath

  scrapeAndZip: (url, targetDir) ->
    tempDir = @configuration.getTempPreviewStorageDirectory()

    zipFile = null
    tempDir = tempDir
    options =
      urls: [url],
      directory: tempDir

    outDir = if !targetDir then @configuration.getOutDir() else targetDir
    outFile = path.join(outDir, "#{@extractName(url)}_#{@now()}.zip")

    scrape(options)
    .then () =>
      @zipFolder(tempDir, outFile)
    .then (destination) =>
      @deleteFolder tempDir
      .then () ->
        return destination

module.exports = PreviewArchiver
