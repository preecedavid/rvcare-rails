# frozen_string_literal: true

class Partner < ApplicationRecord
  has_many :partner_reports

  resourcify

  def current_report
    partner_reports.find_by(year: Date.today.year)
  end
end
