# frozen_string_literal: true

require 'rails_helper'

module ReportsImport
  RSpec.describe TdBankReportImporter do
    let(:year) { Date.today.year }

    let!(:partner_report) do
      FactoryBot.create(:partner_report, year: year, type: 'NtpReport')
    end

    describe '#call' do
      let(:dealer) { FactoryBot.create(:dealer, td_account: 6.times.map { rand(10).to_s }.join) }
      let(:fake_file) { instance_double('ActionDispatch::Http::UploadedFile', original_filename: 'fake file') }

      subject { described_class.new(file: fake_file, partner_report: partner_report) }

      context 'valid input data' do
        before { allow(subject).to receive(:data).and_return(input_data) }

        let(:input_data) do
          [
            { td_account: dealer.td_account, units: 10, reported_on: "#{year}-04-10", market_share_reached: 'true',
        first_look: 'true' },
            { td_account: dealer.td_account, units: 17, reported_on: "#{year}-04-11", market_share_reached: 'false',
        first_look: 'false' },
          ]
        end

        it 'adds records to entries table' do
          expect { subject.call }.to change(Entry, 'count').by(input_data.size)
        end

        it 'saves the correct data', :aggregate_failures do
          subject.call
          entries = Entry.last(2)

          expect(entries.map(&:type)).to all(eq("Units"))
          expect(entries.map(&:partner_report_id)).to all(eq(partner_report.id))
          expect(entries.map(&:dealer_id)).to all(eq(dealer.id))
          expect(entries.map(&:reported_on)).to contain_exactly(Date.parse("2021-04-10"), Date.parse("2021-04-11"))
          expect(entries.map(&:value)).to contain_exactly(10, 17)
          expect(entries.map(&:extra)).to \
            contain_exactly(
              { 'market_share_reached' => true, 'first_look' => true },
              { 'market_share_reached' => false, 'first_look' => false }
            )
        end

        context 'report is uploaded the second time' do
          let(:input_data) do
            [
              { td_account: dealer.td_account, units: 10, reported_on: "#{year}-04-10", market_share_reached: 'true',
        first_look: 'true' },
              { td_account: dealer.td_account, units: 17, reported_on: "#{year}-04-11", market_share_reached: 'false',
        first_look: 'false' },
            ]
          end

          before do
            allow(subject).to receive(:data).and_return(input_data)
            Entry.delete_all
            input_data.each do |item|
              Units.create!(
                partner_report_id: partner_report.id,
                dealer_id: dealer.id,
                value: 8,
                reported_on: item[:reported_on],
                extra: { market_share_reached: true, first_look: false }
              )
            end
          end

          it "doesn't create new entries" do
            expect { subject.call }.to_not change(Units, :count)
          end

          it "updates the values" do
            expect { subject.call }.to \
              change { Units.pluck(:value) }.from([8, 8]).to([10, 17])
          end

          it "updates the extra 'market_share_reached' field" do
            expect { subject.call }.to \
              change { Units.all.map { |u| u.extra['market_share_reached'] }}
                .from([true, true]).to([true, false])
          end

          it "updates the extra 'first_look' field" do
            expect { subject.call }.to \
              change { Units.all.map { |u| u.extra['first_look'] }}
                .from([false, false]).to([true, false])
          end
        end
      end

      context 'wrong input data' do
        context 'worng file format' do
          let(:input_data) { "fake input data" }

          before do
            allow(SmarterCSV).to receive(:process).and_raise('Wrong file format')
          end

          it 'returns nil' do
            expect(subject.call).to be_nil
          end

          it 'contains the error' do
            subject.call
            expect(subject.errors).to \
              contain_exactly(a_hash_including(message: /Processing csv file error/))
          end
        end

        context 'wrong dealer_id' do
          before { allow(subject).to receive(:data).and_return(input_data) }

          let(:input_data) do
            [{ td_account: 'unexistent sal account', units: 10, reported_on: "#{year}-04-10" }]
          end

          it "doesn't create new entry" do
            Entry.delete_all
            expect { subject.call }.to_not change(Entry, 'count').from(0)
          end

          it 'records the error information to logs' do
            subject.call
            expect(subject.logs).to \
              contain_exactly(a_hash_including(success: false, message: "error: dealer not found"))
          end
        end

        [:units, :reported_on].each do |absent_field|
          context "#{absent_field} absence" do
            before do
              input_data.first[absent_field] = nil
              allow(subject).to receive(:data).and_return(input_data)
              Entry.delete_all
            end

            let(:input_data) do
              [{ td_account: dealer.td_account, units: 10, reported_on: "#{year}-04-10" }]
            end

            it "doesn't create new entry" do
              expect { subject.call }.to_not change(Entry, 'count').from(0)
            end

            it 'records the error information to logs' do
              subject.call
              expect(subject.logs).to \
                contain_exactly(a_hash_including(success: false, message: /error: .+ can't be blank/))
            end
          end
        end

        context 'wrong year' do
          before { allow(subject).to receive(:data).and_return(input_data) }

          let(:input_data) do
            [
              { td_account: dealer.td_account, units: 10, reported_on: "#{year-1}-04-10", market_share_reached: 'true',
          first_look: 'true' },
              { td_account: dealer.td_account, units: 17, reported_on: "#{year-1}-04-11", market_share_reached: 'false',
          first_look: 'false' },
            ]
          end

          it "doesn't create new entry" do
            Entry.delete_all
            expect { subject.call }.to_not change(Entry, 'count').from(0)
          end

          it 'records the error information to logs' do
            subject.call
            expect(subject.logs).to \
              all(a_hash_including(success: false, message: /error: the date doesn't match the reporting year/))
          end
        end
      end
    end
  end
end
