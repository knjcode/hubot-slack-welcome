# Description
#   Display welcome message when someone joins your slack channel
#
# Configuration:
#   HUBOT_SLACK_WELCOME_TARGET_CHANNEL - set target channel (default. general)
#   HUBOT_SLACK_WELCOME_MESSAGE        - set welcome message (default. Welcome!)
#   HUBOT_SLACK_WELCOME_BOT_NAME       - set custom bot name in welcome message (default. hubot name)
#   HUBOT_SLACK_WELCOME_ICON_URL       - set custom bot icon in welcome message (default. hubot icon)
#   SLACK_INVITER_API_ENDPOINT         - set slack-inviter-api endpoint
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
slackInviterApiEndpoint = process.env.SLACK_INVITER_API_ENDPOINT
slackInviterApiToken = process.env.SLACK_INVITER_API_TOKEN

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

  robot.enter (msg) ->
    enterChannel =
      if hubotSlackVersion is 3
        msg.envelope.room
      else if hubotSlackVersion is 4
        robot.adapter.client.rtm.dataStore.getChannelGroupOrDMById(msg.envelope.room).name

    if enterChannel is targetChannel
      # Need hubot-slack v4
      if msg.envelope.user.id[0] is 'U' # ignore bot user
        requestURI = "#{slackInviterApiEndpoint}/users/#{msg.envelope.user.id}/inviter"
        robot.http(requestURI)
          .header('Authorization', "Bearer #{slackInviterApiToken}")
          .get() (err, res, body) ->
            if err
              robot.logger.error err
              return
            response = JSON.parse(body)
            robot.logger.debug response
            if response['status'] is 200
              invitor_id = response['inviter_id']
              invitor_name = robot.adapter.client.rtm.dataStore.getUserById(invitor_id).name
              robot.logger.debug "join_user: #{msg.envelope.user.name} invitor: #{invitor_name}"

              message = "@#{msg.envelope.user.name}:\n#{welcomeMessage}\n招待者の @#{invitor_name} さんはプロフ記入等のフォローお願いします"

              requestURI = "https://slack.com/api/chat.postMessage?" +
                           "token=#{process.env.HUBOT_SLACK_TOKEN}&" +
                           "channel=#{targetChannel}&" +
                           "text=#{encodeURIComponent(message)}&" +
                           "link_names=1&"
              if process.env.HUBOT_SLACK_WELCOME_BOT_NAME
                requestURI += "username=#{name}&icon_url=#{icon}"
              else
                requestURI += "as_user=true"

              robot.http(requestURI)
                .get() (err, res, body) ->
                  if err
                    robot.logger.error err
                  robot.logger.info body
