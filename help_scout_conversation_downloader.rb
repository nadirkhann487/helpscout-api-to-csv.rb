# frozen_string_literal: true

require 'csv'
require 'date'
require 'net/http'
require 'json'
require 'fileutils'

class HelpScoutConversationDownloader
  AUTH_ENDPOINT = URI('https://api.helpscout.net/v2/oauth2/token')

  def initialize(app_id, app_secret, mailbox_id)
    @app_id = app_id
    @app_secret = app_secret
    @mailbox_id = mailbox_id

    download_conversations_to_csv
  end

  def download_conversations_to_csv
    token = auth_token
    return unless token

    parent_folder = 'conversations'
    FileUtils.mkdir_p(parent_folder)
    all_conversations = false
    page = 1

    headers = ['ID', 'Threads Count', 'Customer Name', 'Customer email addresses', 'Assignee', 'Status', 'Subject',
               'Created At', 'Closed At', 'Closed By', 'Resolution Time (seconds)']
    CSV.open('conversations.csv', 'w', write_headers: true, headers: headers, encoding: 'utf-8') do |csv|
      until all_conversations
        conversations = conversations(page)
        break unless conversations

        conversations['_embedded']['conversations'].each do |convo|
          next unless convo['primaryCustomer'].key?('email')

          customer_name = "#{convo['primaryCustomer']['first']} #{convo['primaryCustomer']['last']}"
          assignee = convo['assignee'].nil? ? '' : "#{convo['assignee']['first']} #{convo['assignee']['last']}"
          subject = convo['subject'].nil? ? 'No subject' : convo['subject']
          closed_at = convo['closedAt'].nil? ? '' : convo['closedAt']
          closed_by = ''
          resolution_time = 0

          if convo.key?('closedByUser') && convo['closedByUser']['id'] != 0
            closed_by = "#{convo['closedByUser']['first']} #{convo['closedByUser']['last']}"
            created_date_time = DateTime.strptime(convo['createdAt'], '%Y-%m-%dT%H:%M:%S%z')
            closed_date_time = DateTime.strptime(convo['closedAt'], '%Y-%m-%dT%H:%M:%S%z')
            resolution_time = (closed_date_time - created_date_time).to_i
          end

          threads = threads(convo['id'])['_embedded']['threads']

          convo_folder = File.join(parent_folder, "#{convo['id']}_#{customer_name}_#{convo['createdAt']}")
          FileUtils.mkdir_p(convo_folder)

          threads.each do |thread|
            creator = "#{thread.dig('createdBy', 'first')} #{thread.dig('createdBy', 'last')}"
            # Create a new file for each thread inside the conversation folder
            thread_file_name = File.join(convo_folder, "#{thread['id']}_#{creator}_#{thread['createdAt']}.json")

            # Open the file and write the thread contents as JSON
            File.write(thread_file_name, thread.to_json)
          end

          csv << [
            convo['id'],
            convo['threads'],
            customer_name,
            convo['primaryCustomer']['email'],
            assignee,
            convo['status'],
            subject,
            convo['createdAt'],
            closed_at,
            closed_by,
            resolution_time
          ]
        end

        if page == conversations['page']['totalPages']
          all_conversations = true
        else
          page += 1
        end
      end
    end
  end

  private

  def auth_token
    return @auth_token if defined? @auth_token

    post_data = {
      'grant_type' => 'client_credentials',
      'client_id' => @app_id,
      'client_secret' => @app_secret
    }

    response = Net::HTTP.post_form(AUTH_ENDPOINT, post_data)
    response_body = JSON.parse(response.body)

    @auth_token = response_body['access_token']
  end

  def conversations(page)
    request("https://api.helpscout.net/v2/conversations?status=all&mailbox=#{@mailbox_id}&page=#{page}")
  end

  def threads(id)
    request("https://api.helpscout.net/v2/conversations/#{id}/threads")
  end

  def request(url)
    endpoint = URI(url)

    http = Net::HTTP.new(endpoint.host, endpoint.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(endpoint.request_uri)
    request['Authorization'] = "Bearer #{auth_token}"

    response = http.request(request)
    response_body = JSON.parse(response.body)

    response_body if response.is_a?(Net::HTTPSuccess)
  end
end
