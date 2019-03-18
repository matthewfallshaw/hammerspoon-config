hs.logger.setGlobalLogLevel('warning')
hs.logger.defaultLogLevel = 'warning'
hs.hotkey.setLogLevel('warning')  -- 'cos it ignores global defaults
hs.window.animationDuration = 0.1
-- hs.doc.hsdocs.forceExternalBrowser(true)
hs.doc.hsdocs.moduleEntitiesInSidebar(true)
hs.application.enableSpotlightForNameSearches(true)
hs.allowAppleScript(true)

return {
  -- modules under test
  modules_under_test = {},

  -- spoon.URLDispatcher
  URLDispatcher = {
    url_patterns = {
      -- { <url pattern>, <application bundle ID> },
      { "https?://www.pivotaltracker.com/.*",  "org.epichrome.app.PivotalTrack" },
      { "https?://app.asana.com/.*",           "org.epichrome.app.Asana" },
      { "https?://morty.trikeapps.com/.*",     "org.epichrome.app.Morty" },
      { "https?://app.greenhouse.io/.*",       "org.epichrome.app.Greenhouse" },
      { "https?://workflowy.com/.*",           "com.fluidapp.FluidApp.Workflowy" },
      { "https?://calendar.google.com/.*",     "org.epichrome.app.GoogleCalend" },
      { "https?://www.google.com/calendar/.*", "org.epichrome.app.GoogleCalend" },
      { "https?://calendar.google.com/.*",     "org.epichrome.app.GoogleCalend" },
    },
    default_handler = "com.google.Chrome"
  },

  -- asana
  -- API key
  -- Generated in My Profile Settings -> Apps -> Manage Developer Apps -> Create New Personal Access Token
  asanaApiKey = hs.execute("security find-generic-password -a ${USER} -s Asana -w | tr -d '\n'"),
  -- Names for Asana workspaces used for work and personal
  asanaWorkWorkspaceName = "bellroy.com",
  asanaPersonalWorkspaceName = "Matt & Lina"
}
