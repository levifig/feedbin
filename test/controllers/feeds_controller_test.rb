require 'test_helper'

class FeedsControllerTest < ActionController::TestCase

  setup do
    @user = users(:ben)
  end

  test "update feed" do
    login_as @user

    assert_difference('Tagging.count', 1) do
      xhr :patch, :update, id: @user.feeds.first, feed: {tag_list: "Tag"}
      assert_response :success
    end
  end

  test "rename feed" do
    login_as @user
    feed = @user.feeds.first
    title = Faker::Lorem.sentence
    xhr :patch, :rename, feed_id: feed, feed: {title: title}
    assert @user.subscriptions.where(title: title, feed: feed).length == 1
  end

  test "view modes" do
    login_as @user

    %w{view_unread view_starred view_all}.each do |view_mode|
      xhr :get, view_mode
      assert_response :success
      assert @user.reload.view_mode == view_mode
    end

  end

  test "gets auto_update" do
    login_as @user
    xhr :get, :auto_update
    assert_response :success
  end

  test "push subscribe/unsubscribe" do

    feed = Feed.first
    secret = Push::hub_secret(feed.id)

    params = {
      'id' => feed.id,
      'hub.topic' => feed.feed_url,
      'hub.verify_token' => secret,
      'hub.lease_seconds' => 10_000,
    }

    subscribe_challenge = Faker::Internet.slug
    get :push, params.merge('hub.mode' => 'subscribe', 'hub.challenge' => subscribe_challenge)
    assert_response :success
    assert_equal subscribe_challenge, @response.body
    assert_not_nil feed.reload.push_expiration

    unsubscribe_challenge = Faker::Internet.slug
    get :push, params.merge('hub.mode' => 'unsubscribe', 'hub.challenge' => unsubscribe_challenge)
    assert_response :success
    assert_equal unsubscribe_challenge, @response.body
  end

  test "push needs valid secret" do

    feed = Feed.first
    secret = Push::hub_secret(feed.id)

    params = {
      'id' => feed.id,
      'hub.topic' => feed.feed_url,
      'hub.verify_token' => "#{secret}s",
      'hub.mode' => 'subscribe',
      'hub.challenge' => Faker::Internet.slug
    }

    get :push, params
    assert_response :not_found
  end


  test "PuSH new content" do
    feed = @user.feeds.first
    Feed.reset_counters(feed.id, :subscriptions)
    body = push_prep(feed)
    raw_post :push, {id: feed.id}, body

    assert_response :success
    assert_equal 1, Sidekiq::Queues["feed_refresher_fetcher_critical"].size
  end

  test "PuSH unsubscribe" do
    Sidekiq::Worker.clear_all

    feed = @user.feeds.first
    body = push_prep(feed)
    raw_post :push, {id: feed.id}, body

    assert_response :success
    assert_equal 1, Sidekiq::Queues["feed_refresher_fetcher"].size
  end

  test "modify toggle update settings" do
    login_as @user
    feed = @user.feeds.first
    subscription = @user.subscriptions.where(feed: feed).take!
    xhr :post, :toggle_updates, id: feed
    assert_response :success
    assert_not_equal subscription.show_updates, subscription.reload.show_updates
  end

  test "get update_styles" do
    login_as @user
    feed = @user.feeds.first
    xhr :get, :update_styles
    assert_response :success
  end

  private

  def push_prep(feed)
    Sidekiq::Worker.clear_all
    secret = Push::hub_secret(feed.id)
    body = 'BODY'
    signature = OpenSSL::HMAC.hexdigest('sha1', secret, body)
    @request.headers["HTTP_X_HUB_SIGNATURE"] = "sha1=#{signature}"
    body
  end


end
