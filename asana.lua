--luacheck: allow defined top

-- Setup core constants
local asana = {}
asana.baseUrl = "https://app.asana.com/api/1.0"
asana.reqHeader = {["Authorization"] = "Bearer " .. init.consts.asanaApiKey}
asana.userId = nil
asana.workspaceIds = {}

-- Get Asana userId and workspaceIds
function asana.getIds()
  local _, res, _ = hs.http.get(asana.baseUrl .. "/users/me", asana.reqHeader)
  res = hs.json.decode(res)
  asana.userId = res.data.id
  hs.fnutils.each(
    res.data.workspaces,
    function(x)
      asana.workspaceIds[x.name] = x.id
    end
  )
end

-- Creates a new Asana task with a given name in a given workspace
-- First time function is called it retrieves IDs
function asana.newTask(taskName, workspaceName)
  if not asana.userId then
    asana.getIds()
  end
  hs.http.asyncPost(
    string.format(
      "%s/tasks?assignee=%i&workspace=%i&name=%s",
      asana.baseUrl,
      asana.userId,
      asana.workspaceIds[workspaceName],
      hs.http.encodeForQuery(taskName)
    ),
    "", -- requires empty body
    asana.reqHeader,
    function(code, res)
      if code == 201 then
        hs.notify.show("Asana", "", "New task added to workspace: " .. workspaceName)
      else
        hs.notify.show("Asana", "", "Error adding task")
        print(res)
        hs.toggleConsole()
      end
    end
  )
end

return asana
