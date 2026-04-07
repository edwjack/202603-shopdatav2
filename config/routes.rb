Rails.application.routes.draw do
  root "dashboard#index"

  resources :categories, only: [:index, :show, :edit, :update]

  resources :recommendations, only: [:index, :show] do
    member do
      patch :approve
      patch :reject
      patch :hold
    end
  end

  resources :products, only: [:index, :show] do
    member do
      patch :publish_shopify
    end
    collection do
      post :batch_publish_shopify
    end
  end

  resources :jobs, only: [:index] do
    collection do
      post :run
    end
  end

  namespace :api do
    resources :products, only: [] do
      collection do
        post :batch_upsert
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
