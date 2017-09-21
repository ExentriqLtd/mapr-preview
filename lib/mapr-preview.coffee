Configuration = require './util/configuration'
BitBucketManager = require './util/bitbucket-manager'
RenderingProcessManager = require './util/rendering-process-manager'
PreviewView = require './preview-view'
ProgressView = require './util/progress-view'
getFolderSize = require('get-folder-size')
git = require './util/git'
PanelView = require './util/panel-view'

q = require 'q'

# TODO: remove as long as it's merged into master
THE_BRANCH = "feature/201708/preview"
FOLDER_SIZE_INTERVAL = 1500

ICON_PREVIEW = 'icon-device-desktop'
ICON_REFRESH = 'icon-sync'

{CompositeDisposable, TextEditor} = require 'atom'

cleanupPath = (path) ->
  cleanedUpPath = path.replace(/\\/g,"/")
  cleanedUpPath = cleanedUpPath.substring(0, cleanedUpPath.lastIndexOf '/')
  cleanedUpPath = cleanedUpPath.substring(1) if cleanedUpPath.startsWith '/'
  return cleanedUpPath

module.exports = MaprPreview =
  subscriptions: null
  configuration: new Configuration()
  renderingProcessManager: null
  thebutton: null
  previewView: null
  panelView: null
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
    console.log @thebutton
    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

  setIconPreview: () ->
    if !@thebutton?
      return

    classList = @thebutton.element.classList
    classList.remove ICON_REFRESH
    classList.remove ICON_PREVIEW

    classList.add ICON_PREVIEW

  setIconRefresh: () ->
    if !@thebutton?
      return

    classList = @thebutton.element.classList
    classList.remove ICON_PREVIEW
    classList.remove ICON_REFRESH

    classList.add ICON_REFRESH

  activate: (state) ->
    console.log "Activating mapr-preview"
    if !@configuration.isAweConfValid()
      return
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'mapr-preview:preview': => @preview()

    @subscriptions.add atom.workspace.onDidDestroyPaneItem (event) =>
      # console.log "Destroy pane item", event
      if event.item instanceof PanelView
        @renderingProcessManager.killPagePreview()
        @previewView.destroy() if @previewView?.destroy
        @previewView = null
        @panelView = null
        @setIconPreview()

    @subscriptions.add atom.workspace.observeActiveTextEditor (editor) =>
      @showButtonIfNeeded editor
      path = editor.getPath()
      if @configuration.isPathFromProject(path)
        editor.terminatePendingState()
        
    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

    if !@configuration.exists() || !@configuration.isValid()
      @configure()
    else
      projectCloned = !@configuration.shouldClone()
      # console.log "Project cloned?", projectCloned
      if projectCloned
        git.init(@configuration.getTargetDir())
        #TODO: update THE_BRANCH. It will be removed
        @isBranchRemote(THE_BRANCH)
          .then (isRemote) ->
            # console.log THE_BRANCH, isRemote
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
      # console.log branches, isRemote, isLocal, branch
      return isRemote && !isLocal

  showButtonIfNeeded: (editor) ->
    # console.log "showButtonIfNeeded", editor
    if !editor
      @thebutton?.setEnabled false
      @setIconPreview()
      return
    path = editor?.getPath()
    @thebutton?.setEnabled(@ready && path.endsWith(".md") && @configuration?.isPathFromProject path) if path?

    # If path is the same in preview -> ICON_REFRESH
    # Else -> ICON_PREVIEW
    if !@renderingProcessManager?
      @setIconPreview()
      return

    relativePath = @configuration.relativePath(path)
    if @renderingProcessManager.path == relativePath
      @setIconRefresh()
    else
      @setIconPreview()


  configure: ->
    # console.log 'MaprPreview shown configuration'

    if !(@configuration.exists() && @configuration.isValid())
      @configuration.acquireFromAwe()
      @configuration.save()
      @afterConfigure()

  afterConfigure: ->
    validationMessages = @configuration.validateAll().map (k) ->
      Configuration.reasons[k]
    if validationMessages.length == 0
      projectCloned = !@configuration.shouldClone()
      if !projectCloned
        atom.notifications.addInfo("MapR.com project is being downloaded. Atom will restart afterwards.")
        @doClone()
    else
      validationMessages.forEach (msg) ->
        atom.notifications.addError(msg)

  deactivate: ->
    @subscriptions.dispose()
    @renderingProcessManager?.killPagePreview()

  serialize: ->

  preview: () ->
    currentEditor = atom.workspace.getActiveTextEditor()
    if !currentEditor
      return
    # console.log currentEditor

    if currentEditor.getPath
      path = currentEditor.getPath()
    else
      return

    if !@configuration.isPathFromProject path || !path.endsWith('.md')
      return

    path = @configuration.relativePath(path)
    # if path.startsWith '/'
    #   path = path.substring(1)

    conf = @configuration.get()
    if !@renderingProcessManager?
      @renderingProcessManager = new RenderingProcessManager(@configuration.getTargetDir(), conf.contentDir)
      @setIconRefresh()

    # if @renderingProcessManager.alreadyRunning()
    #   atom.notifications.addWarning("Preview is already running")
    #   return

    cleanedUpPath = cleanupPath(path)

    @renderingProcessManager.checkNodeEnvironment()
      # .then () => @renderingProcessManager.checkPortInUse()
      # .then (inUse) =>
      .then () =>
        # if !inUse
        if @previewView?
          @destroyPreviewView()
        @previewView = new PreviewView()
        @previewView.initialize()
        @panelView = new PanelView("MapR Preview", "mpw://#{cleanedUpPath}", @previewView)
        atom.workspace.open(@panelView, {})
          .then (pane) =>
            @renderingPane = pane
          .then () =>
            @renderingProcessManager.pagePreview(path)
          .then () =>
            @previewView.setFile(cleanedUpPath)
          .catch (error) ->
            console.log "Rendering process said", error
            atom.notifications.addError "Error occurred", description: error.message
        # else
        #   atom.notifications.addError "Port 8080 is use", description: "A process is listening to port 8080.\nMake sure you stop it before you launch page preview."
      .fail (error) ->
        console.log "Rendering process said", error
        atom.notifications.addError "Error occurred", description: error

  destroyPreviewView: () ->
    atom.workspace.getPanes().forEach (pane) =>
      pane.destroyItem @panelView
  doClone: () ->
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
                  percent = percentage(currentSize, repoSize)
                  console.log "Cloning", currentSize, repoSize, percent, '%'
                  progress.setProgress percent
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
