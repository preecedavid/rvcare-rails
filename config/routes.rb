# frozen_string_literal: true

Rails.application.routes.draw do
  ActiveAdmin.routes(self)

  devise_for :users, controllers: {
    passwords: 'users/passwords',
    sessions: 'users/sessions',
    registrations: 'users/registrations',
    unlocks: 'users/unlocks'
  }

  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  resource :dashboard, only: %i[show update]
  resources :widgets, only: [:show]
  resources :dealers, only: %i[edit update] do
    resources :reports, controller: :dealer_reports
  end

  resources :report_uploads, only: %i[new create] do
    collection do
      get 'new_admin'
    end
  end

  get 'fullscreen_dashboard/show'

  root 'fullscreen_dashboard#show'
end
