# Description
#   Display welcome message when someone joins your slack channel
#
# Configuration:
#   HUBOT_SLACK_WELCOME_TARGET_CHANNEL - set target channel (default. general)
#   HUBOT_SLACK_WELCOME_MESSAGE        - set welcome message (default. Welcome!)
#   HUBOT_SLACK_WELCOME_BOT_NAME       - set custom bot name in welcome message (default. hubot name)
#   HUBOT_SLACK_WELCOME_ICON_URL       - set custom bot icon in welcome message (default. hubot icon)
#   SLACK_INVITER_API_URL              - set slack-inviter-api URL
#   SLACK_INVITER_API_TOKEN            - set slack-inviter-api access token
#
# Commands:
#   None
#
# Author:
#   knjcode <knjcode@gmail.com>

targetChannel = process.env.HUBOT_SLACK_WELCOME_TARGET_CHANNEL ? 'general'
welcomeMessage = process.env.HUBOT_SLACK_WELCOME_MESSAGE ? 'Welcome!'
welcomeMessage = welcomeMessage.replace(/\\n/g, '\n')
slackInviterApiUrl = process.env.SLACK_INVITER_API_URL
slackInviterApiToken = process.env.SLACK_INVITER_API_TOKEN

rp = require 'request-promise'

module.exports = (robot) ->
  if robot.adapter?.client?._apiCall?
    hubotSlackVersion = 3
  else if robot.adapter?.client?.rtm?.dataStore?.users?
    hubotSlackVersion = 4
  else
    robot.logger.error "hubot-slack-welcome: Failed to detect hubot-slack version"

  name = process.env.HUBOT_SLACK_WELCOME_BOT_NAME ? robot.name
  icon = process.env.HUBOT_SLACK_WELCOME_ICON_URL ?
    if hubotSlackVersion is 3
      robot.brain.data.users[robot.adapter.self.id]
    else if hubotSlackVersion is 4
      robot.adapter.client.rtm.dataStore.users[robot.adapter.self.id].profile.image_48

  robot.logger.info "hubot-slack-welcome: wait for user at ##{targetChannel}"

  createChatPostURI = (msg) ->
    requestURI = "https://slack.com/api/chat.postMessage?" +
                 "token=#{process.env.HUBOT_SLACK_TOKEN}&" +
                 "channel=#{targetChannel}&" +
                 "text=#{encodeURIComponent(msg)}&" +
                 "link_names=1&"
    if process.env.HUBOT_SLACK_WELCOME_BOT_NAME
      requestURI += "username=#{name}&icon_url=#{icon}"
    else
      requestURI += "as_user=true"
    requestURI

  createGetInviterOptions = (userId) ->
    getInviterOptions =
      uri: "#{slackInviterApiUrl}/users/#{userId}/inviter"
      headers:
        Authorization: "Bearer #{slackInviterApiToken}"
      json: true

  createGetChannelsListOptions = ->
    getChannelsListOptions =
      uri: "https://slack.com/api/channels.list?token=#{process.env.HUBOT_SLACK_TOKEN}"
      json: true

  robot.enter (msg) ->
    enterChannel =
      if hubotSlackVersion is 3
        msg.envelope.room
      else if hubotSlackVersion is 4
        robot.adapter.client.rtm.dataStore.getChannelGroupOrDMById(msg.envelope.room).name

    if enterChannel is targetChannel
      # Need hubot-slack v4
      unless msg.envelope.user.is_bot # ignore bot user
        message = "@#{msg.envelope.user.name}:\n#{welcomeMessage}"

        inviterOptions = createGetInviterOptions(msg.envelope.user.id)
        rp(inviterOptions)
          .then (res) ->
            robot.logger.debug res
            inviter_id = res['inviter_id']
            inviter_name = robot.adapter.client.rtm.dataStore.getUserById(inviter_id).name
            robot.logger.debug "join_user: #{msg.envelope.user.name} inviter: #{inviter_name}"

            message += "\n招待者の @#{inviter_name} さんはプロフ記入等のフォローお願いします"

            channelsListOptions = createGetChannelsListOptions()
            rp(channelsListOptions)
          .then (res) ->
            channel = res.channels.filter (channel) -> channel.name is targetChannel
            numOfChannelMembers = channel[0].num_members

            message += "\n(#{msg.envelope.user.name}さんはこのchannelの#{numOfChannelMembers}人目のメンバーです)"
          .catch (error) ->
            # failed to get inviter
            robot.logger.debug error
          .finally ->
            chatPostURI = createChatPostURI(message)
            rp(chatPostURI)
