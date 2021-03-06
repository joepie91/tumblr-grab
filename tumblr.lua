dofile("table_show.lua")
dofile("urlcode.lua")

local item_type = os.getenv('item_type')
local item_value = string.gsub(os.getenv('item_value'), "%-", "%%-")
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local ids = {}

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

-- Tumblr seem to be using epoch time on the /archive endpoint
-- Goal: Get more posts, using epoch minus time in seconds for each month
local epochtime = 1543953699
local epochpermonth = 2629743
local concat = "^https?://".. item_value .. "%.tumblr%.com/?.*/?.*/?.*/?.*/?.*$"
local video = "^https?://www%.tumblr%.com/video/".. item_value .. "/?.*/?.*/?.*"

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
  or string.match(url, "[<>\\%*%$;%^%[%],%(%)]")
  or string.match(url, "//$")
  or string.match(url, "^https?://ns%.adobe%.com")
  or string.match(url, "^https?://www%.change%.org")
  or string.match(url, "^https?://[^.]+/") 
  or string.match(url, "^https?://radar%.cedexis%.com")
  or string.match(url, "^https?://[0-9]+%.media%.tumblr%.com/%p+%d+")
  or string.match(url, "^https?://assets%.tumblr%.com/%p+%d+")
  or string.match(url, "^https?://static%.tumblr%.com/%p+%d+")
  or string.match(url, "^https?://[0-9]+%.media%.tumblr%.com/avatar_[a-zA-Z0-9]+_64%.pnj")
  or string.match(url, "^https?://[0-9]+%.media%.tumblr%.com/post/")
  or string.match(url, "^https?://assets%.tumblr%.com/archive")
  or string.match(url, "^https?://assets%.tumblr%.com/filter%-by")
  or string.match(url, "^https?://assets%.tumblr%.com/client")
  or string.match(url, "^https?://static%.tumblr%.com/[%u%p%l]+")
  or string.match(url, "ios%-app://") then
    return false
  end
  
  if string.match(url, concat) then
    if parenturl ~= nil then
      if string.match(parenturl, concat) or string.match(url, "^https?://www%.tumblr%.com/") then
        return true
      else
        return false
      end
    end
    return true
  end
  
  if string.match(url, video) then
    return true
  end
  
  if string.match(url, "^https?://assets%.tumblr%.com")
  or string.match(url, "^https?://static%.tumblr%.com")
  or string.match(url, "^https?://[0-9]+%.media%.tumblr%.com") then
    if parenturl ~= nil then
      if string.match(parenturl, concat) then
        return true
      end
    else
      return true
    end
  end
  
  if string.match(url, "^https?://[a-z]+%.media%.tumblr%.com") then
    if parenturl ~= nil then
      if string.match(parenturl, "^https?://www%.tumblr%.com") then
        return true
      end
    else
      return true
    end
  end
  
  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]
  
  if string.find(url, "px.srvcs.tumblr.com") then
    -- Ignore px.srvcs.tumblr.com tracking domain
    return false
  end
  
  if (downloaded[url] ~= true and addedtolist[url] ~= true)
  and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(url, "&amp;", "&")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
       and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end
  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)")..newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)")..string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end
  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  if allowed(url, nil) then
    html = read_file(file)
    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
       checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      check(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500 or
    (status_code > 400 and status_code < 403 and status_code ~= 404)
    or status_code > 404 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 10")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if string.match(url["url"], "_%d+.[pjg][npi][ggf]$") then
        return wget.actions.EXIT
      end
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end
  
  if status_code == 403 or status_code == 400 or status_code == 0 then
    --if string.match(url["host"], "")
    if string.match(url["host"], "assets%.tumblr%.com")
    or string.match(url["host"], "static%.tumblr%.com")
    or string.match(url["host"], "[a-z0-9]+%.media%.tumblr%.com")
    or string.match(url["host"], "vtt%.tumblr%.com")
    or string.match(url["host"], "www%.tumblr%.com") then
      io.stdout:write("Server returned " ..http_stat.statcode.." ("..err.."). Skipping.\n")
      tries = 0
      return wget.actions.EXIT
    else
      io.stdout:write("Server returned " ..http_stat.statcode.." ("..err.."). Sleeping.\n")
      io.stdout:flush()
      os.execute("sleep 1")
      tries = tries + 1
      if tries >= 5 then
        io.stdout:write("\nI give up...\n")
        io.stdout:flush()
        tries = 0
        if allowed(url["url"], nil) then
          return wget.actions.ABORT
        else
          return wget.actions.EXIT
        end
      else
        return wget.actions.CONTINUE
      end
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end