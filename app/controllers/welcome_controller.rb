class WelcomeController < ApplicationController
  layout 'site'
  
  def index
    if @current_user
      render_component :controller => "publications", :action => "index"
    end
  end
end
