class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@vulnsentry.com"
  layout "mailer"
end
