ConfigurationView = require './configuration-view'
Configuration = require './util/configuration'
BitBucketManager = require './util/bitbucket-manager'
RenderingProcessManager = require './util/rendering-process-manager'
PreviewView = require './preview-view'
ProgressView = require './util/progress-view'
getFolderSize = require('get-folder-size')
git = require './util/git'

q = require 'q'

# TODO: remove as long as it's merged into master
THE_BRANCH = "feature/201708/preview"
FOLDER_SIZE_INTERVAL = 1500

{CompositeDisposable, TextEditor} = require 'atom'

module.exports = MaprPreview =
  maprPreviewView: null
  panel: null
  subscriptions: null
  configuration: new Configuration()
  renderingProcessManager: null
  thebutton: null
  previewView: null
  ready: false

  consumeToolBar: (getToolBar) ->
    if !@configuration.isAweConfValid()
      return
    @toolBar = getToolBar('mapr-preview')
    @toolBar.addSpacer
      priority: 99

    @thebutton = @toolBar.addButton
      icon: 'device-desktop',
      callback: 'mapr-preview:preview',
      tooltip: 'MapR Preview'
      priority: 100

    @thebutton.setEnabled false
    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

  activate: (state) ->
    if !@configuration.isAweConfValid()
      return
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'mapr-preview:preview': => @preview()

    @subscriptions.add atom.workspace.addOpener (uri) =>
      if uri.startsWith 'mpw://'
        @previewView = new PreviewView()
        @previewView.initialize()
        return @previewView

    @subscriptions.add atom.workspace.onDidDestroyPaneItem (event) =>
      console.log "Destroy pane item", event
      if event.item.classList && event.item.classList[0] == "mapr-preview"
        @renderingProcessManager.killPagePreview()
        @previewView.destroy() if @previewView.destroy
        @previewView = null

    @subscriptions.add atom.workspace.observeActiveTextEditor (editor) => @showButtonIfNeeded editor
    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

    if !@configuration.exists() || !@configuration.isValid()
      @configure()
    else
      projectCloned = !@configuration.shouldClone()
      console.log "Project cloned?", projectCloned
      if projectCloned
        git.init(@configuration.getTargetDir())
        #TODO: update THE_BRANCH. It will be removed
        @isBranchRemote(THE_BRANCH)
          .then (isRemote) ->
            console.log THE_BRANCH, isRemote
            prefix = ''
            prefix = 'origin/' if isRemote
            git.checkout "#{prefix}#{THE_BRANCH}", isRemote
          .then () ->
            git.pull()
          .then () =>
            @ready = true
            @showButtonIfNeeded atom.workspace.getActiveTextEditor()
          .fail (e) =>
            atom.notifications.addError "Unable to update MapR.com. Preview won't be available.",
              description: e.message + "\n" + e.stdout
            @ready = false
            @showButtonIfNeeded atom.workspace.getActiveTextEditor()
      else
        @doClone()

  isBranchRemote: (branch) ->
    return git.getBranches().then (branches) ->
      isRemote = branches.remote
        .filter (b) -> b == 'origin/' + branch
        .length > 0
      isLocal = branches.local
        .filter (b) -> b == branch
        .length > 0
      console.log branches, isRemote, isLocal, branch
      return isRemote && !isLocal

  showButtonIfNeeded: (editor) ->
    path = editor?.getPath()
    @thebutton?.setEnabled(@ready && path.endsWith(".md") && @configuration?.isPathFromProject path) if path?

  configure: ->
    console.log 'MaprPreview shown configuration'

    if !(@configuration.exists() && @configuration.isValid())
      @configuration.acquireFromAwe()

    @configurationView = new ConfigurationView(@configuration,
      () => @saveConfig(),
      () => @hideConfigure()
    )
    @panel = atom.workspace.addTopPanel(item: @configurationView.getElement(), visible: false) if !@panel?
    @panel.show()

  saveConfig: ->
    console.log "MaprPreview Save configuration"
    confValues = @configurationView.readConfiguration()
    @configuration.setValues(confValues)

    validationMessages = @configuration.validateAll().map (k) ->
      Configuration.reasons[k]
    if validationMessages.length == 0
      @configuration.save()
      @hideConfigure()

      projectCloned = !@configuration.shouldClone()
      if !projectCloned
        atom.notifications.addInfo("MapR.com project is being downloaded. Atom will restart afterwards.")
        @doClone()
    else
      validationMessages.forEach (msg) ->
        atom.notifications.addError(msg)

  hideConfigure: ->
    console.log 'MaprPreview hidden configuration'
    @panel.destroy()
    @panel = null

  deactivate: ->
    @panel?.destroy()
    @subscriptions.dispose()
    @configurationView?.destroy()
    @renderingProcessManager?.killPagePreview()

  serialize: ->

  preview: () ->
    currentPaneItem = atom.workspace.getActivePaneItem()
    if !currentPaneItem instanceof TextEditor
      return

    if currentPaneItem.getPath
      path = currentPaneItem.getPath()
    else
      return

    if !@configuration.isPathFromProject path || !path.endsWith('.md')
      return

    path = @configuration.relativePath(path)
    if path.startsWith '/'
      path = path.substring(1)

    conf = @configuration.get()
    if !@renderingProcessManager?
      @renderingProcessManager = new RenderingProcessManager(@configuration.getTargetDir(), conf.contentDir)
      # atom.notifications.addInfo "Preview rendering started",
      #   description: "It may take a while. A new tab will open when the preview is ready."

    cleanedUpPath = path.replace(/\\/g,"/").substring(0, path.lastIndexOf '/')
    atom.workspace.open("mpw://#{cleanedUpPath}")
      .then (pane) =>
        console.log pane
        @renderingPane = pane
      .then () => @renderingProcessManager.pagePreview(path)
      .then () => @previewView.setFile(cleanedUpPath)
      .catch (error) ->
        console.log "Rendering process said", error
        atom.notifications.addError "Error occurred",
          description: error.message

  doClone: () ->
    console.log "mapr-preview::doClone"

    folderSizeInterval = -1
    repoSize = -1
    currentSize = 0

    percentage = (value, max) ->
      if value < 0
        return 0
      if value >= max
        return max
      return value / max * 100.0

    conf = @configuration.get()

    callGitClone = () =>
      git.clone conf.repoUrl, @configuration.getTargetDir()
        .then () ->
          atom.restartApplication()
        .fail () ->
          atom.notifications.addError "Error occurred",
          description: "Unable to download mapr.com project"

    return q.fcall () =>
      if @isBitbucketRepo()
        progress = new ProgressView()
        progress.initialize()

        modal = atom.workspace.addModalPanel
          item: progress
          visible: true

        @getBitbucketRepoSize()
          .then (size) =>
            repoSize = size
            promise = callGitClone()
              .then () ->
                window.clearInterval folderSizeInterval
                modal.destroy()
              .fail () ->
                window.clearInterval folderSizeInterval
                modal.destroy()

            folderSizeInterval = window.setInterval () =>
              @getFolderSize @configuration.getTargetDir()
                .then (size) ->
                  currentSize = size
                  console.log "Cloning", currentSize, repoSize
                  progress.setProgress percentage(currentSize, repoSize)
                .fail () -> #maybe not yet there
            , FOLDER_SIZE_INTERVAL
            return promise

          .fail (e) =>
            console.log e
            modal?.destroy()
            atom.confirm
              message: 'Error occurred'
              detailedMessage: "Unable to gather remote repository size.\nYou may want to try again or check out your configuration."
              buttons:
                Configure: => @configure()
                Retry: => @doClone()
      else
        return callGitClone()

  isBitbucketRepo: () ->
    @configuration.get().repoUrl.indexOf('bitbucket.org') > 0

  getBitbucketRepoSize: () ->
    conf = @configuration.get()
    repoOwner = conf.repoOwner
    repoName = @configuration.getRepoName conf.repoUrl
    bm = new BitBucketManager(conf.username, conf.password)
    return bm.getRepoSize(repoOwner, repoName)

  getFolderSize: (folder) ->
    deferred = q.defer()
    getFolderSize folder, (err, size)  ->
      if err
        deferred.reject err
      else
        deferred.resolve size

    return deferred.promise
