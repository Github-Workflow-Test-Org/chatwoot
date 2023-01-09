require 'net/imap'

class Inboxes::FetchImapEmailsJob < ApplicationJob
  queue_as :low

  def perform(channel)
    return unless should_fetch_email?(channel)

    # fetching email for microsoft provider
    fetch_mail_for_ms_provider(channel)
    fetch_mail_for_channel(channel)

    # clearing old failures like timeouts since the mail is now successfully processed
    channel.reauthorized!
  rescue *ExceptionList::IMAP_EXCEPTIONS
    channel.authorization_error!
  rescue EOFError => e
    Rails.logger.error e
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
  end

  private

  def should_fetch_email?(channel)
    channel.imap_enabled? && !channel.reauthorization_required?
  end

  def fetch_mail_for_channel(channel)
    return if channel.microsoft?

    # TODO: rather than setting this as default method for all mail objects, lets if can do new mail object
    # using Mail.retriever_method.new(params)
    Mail.defaults do
      retriever_method :imap, address: channel.imap_address,
                              port: channel.imap_port,
                              user_name: channel.imap_login,
                              password: channel.imap_password,
                              enable_ssl: channel.imap_enable_ssl
    end

    Mail.find(what: :last, count: 10, order: :asc).each do |inbound_mail|
      next if channel.inbox.messages.find_by(source_id: inbound_mail.message_id).present?

      process_mail(inbound_mail, channel)
    end
  end

  def fetch_mail_for_ms_provider(channel)
    return unless channel.microsoft?

    access_token = valid_access_token channel

    return unless access_token

    imap = imap_authenticate(channel, access_token)
    imap.search(['BEFORE', tomorrow, 'SINCE', yesterday]).each do |message_id|
      inbound_mail = Mail.read_from_string imap.fetch(message_id, 'RFC822')[0].attr['RFC822']

      next if channel.inbox.messages.find_by(source_id: inbound_mail.message_id).present?

      process_mail(inbound_mail, channel)
    end
  end

  def imap_authenticate(channel, access_token)
    imap = Net::IMAP.new(channel.imap_address, channel.imap_port, true)
    imap.authenticate('XOAUTH2', channel.imap_login, access_token)
    imap.select('INBOX')
    imap
  end

  def process_mail(inbound_mail, channel)
    Imap::ImapMailbox.new.process(inbound_mail, channel)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
  end

  # Making sure the access token is valid for microsoft provider
  def valid_access_token(channel)
    Channels::RefreshMsOauthTokenJob.new.access_token(channel, channel.provider_config.with_indifferent_access)
  end

  def yesterday
    (Time.zone.today - 1).strftime('%d-%b-%Y')
  end

  def tomorrow
    (Time.zone.today + 1).strftime('%d-%b-%Y')
  end
end
