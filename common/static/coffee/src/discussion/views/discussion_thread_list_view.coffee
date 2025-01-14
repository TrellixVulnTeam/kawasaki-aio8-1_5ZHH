if Backbone?
  class @DiscussionThreadListView extends Backbone.View
    events:
      "click .search": "showSearch"
      "click .home": "goHome"
      "click .browse-dropdown": "toggleTopicDrop"
      "keydown .post-search-field": "performSearch"
      "focus .post-search-field": "showSearch"
      ## search欄の×ボタン
      "click .clearButton": "clearSearch"
      "click .sort-bar a": "sortThreads"
      ## sidebarのアコーディオン化
      "click .drop-menu-parent-category": "toggleAccordion"
      ##"click .browse-topic-drop-menu": "filterTopic"
      "click .drop-menu-meta-category": "filterTopic"
      "click .drop-menu-entry": "filterTopic"
      "click .browse-topic-drop-search-input": "ignoreClick"
      "click .post-list .list-item a": "threadSelected"
      "click .post-list .more-pages a": "loadMorePages"
      "change .cohort-options": "chooseCohort"
      'keyup .browse-topic-drop-search-input': DiscussionFilter.filterDrop

    initialize: ->
      @displayedCollection = new Discussion(@collection.models, pages: @collection.pages)
      @collection.on "change", @reloadDisplayedCollection
      @sortBy = "date"
      @discussionIds=""
      @collection.on "reset", (discussion) =>
        board = $(".current-board").html()
        @displayedCollection.current_page = discussion.current_page
        @displayedCollection.pages = discussion.pages
        @displayedCollection.reset discussion.models
        # TODO: filter correctly
        # target = _.filter($("a.topic:contains('#{board}')"), (el) -> el.innerText == "General" || el.innerHTML == "General")
        # if target.length > 0
        #   @filterTopic($.Event("filter", {'target': target[0]}))
      @collection.on "add", @addAndSelectThread
##      @sidebar_padding = 10
##      @sidebar_header_height = 87
      @boardName
      @template = _.template($("#thread-list-template").html())
      @templateTL = _.template($("#topic-list-template").html())
      @current_search = ""
      @mode = 'all'

    reloadDisplayedCollection: (thread) =>
      thread_id = thread.get('id')
      content = @renderThread(thread)
      ## sidebar コメント等操作バグ対応時に追加
      content.addClass("read")
      current_el = @$("a[data-id=#{thread_id}]")
      active = current_el.hasClass("active")
      ## トピックリストが２か所にあるのでreplaceAllに
      ## current_el.replaceWith(content)
      content.replaceAll(current_el)
      if active
        @setActiveThread(thread_id)


    #TODO fix this entire chain of events
    addAndSelectThread: (thread) =>
      commentable_id = thread.get("commentable_id")
      commentable = @$(".board-name[data-discussion_id]").filter(-> $(this).data("discussion_id").id == commentable_id)
      @setTopicHack(commentable)
      @retrieveDiscussion commentable_id, =>
        @trigger "thread:created", thread.get('id')

    updateSidebar: =>
      ## 本家ではここでsidebarのリサイズをするが、
      ## gaccoではfoundationで横幅調整するので何もしない。
#      scrollTop = $(window).scrollTop();
#      windowHeight = $(window).height();
#
#      discussionBody = $(".discussion-article")
#      discussionsBodyTop = if discussionBody[0] then discussionBody.offset().top
#      discussionsBodyBottom = discussionsBodyTop + discussionBody.outerHeight()
#
#      sidebar = $(".sidebar")
#      if scrollTop > discussionsBodyTop - @sidebar_padding
#        sidebar.css('top', scrollTop - discussionsBodyTop + @sidebar_padding);
#      else
#        sidebar.css('top', '0');
#
#      sidebarWidth = .31 * $(".discussion-body").width();
#      sidebar.css('width', sidebarWidth + 'px');
#
#      sidebarHeight = windowHeight - Math.max(discussionsBodyTop - scrollTop, @sidebar_padding)
#
#      topOffset = scrollTop + windowHeight
#      discussionBottomOffset = discussionsBodyBottom + @sidebar_padding
#      amount = Math.max(topOffset - discussionBottomOffset, 0)
#
#      sidebarHeight = sidebarHeight - @sidebar_padding - amount
#      sidebarHeight = Math.min(sidebarHeight + 1, discussionBody.outerHeight())
#      sidebar.css 'height', sidebarHeight
#
#      postListWrapper = @$('.post-list-wrapper')
#      postListWrapper.css('height', (sidebarHeight - @sidebar_header_height - 4) + 'px')


    # Because we want the behavior that when the body is clicked the menu is
    # closed, we need to ignore clicks in the search field and stop propagation.
    # Without this, clicking the search field would also close the menu.
    ignoreClick: (event) ->
        event.stopPropagation()

    render: ->
      @timer = 0
      @$el.html(@template())
      ## アコーディオン対応のため、topic-listを定義
      $(".topic-list").html(@templateTL())

      $(window).bind "load", @updateSidebar
      $(window).bind "scroll", @updateSidebar
      $(window).bind "resize", @updateSidebar

      @displayedCollection.on "reset", @renderThreads
      @displayedCollection.on "thread:remove", @renderThreads
      @renderThreads()
      @

    renderThreads: =>
      @$(".post-list").html("")
      rendered = $("<div></div>")
      for thread in @displayedCollection.models
        content = @renderThread(thread)
        rendered.append content
        content.wrap("<li class='list-item' data-id='\"#{thread.get('id')}\"' />")

      @$(".post-list").html(rendered.html())
      @renderMorePages()
      @updateSidebar()
      @trigger "threads:rendered"

    renderMorePages: ->
      if @displayedCollection.hasMorePages()
        @$(".post-list").append("<li class='more-pages'><a href='#'>" + gettext("Load more") + "</a></li>")

    loadMorePages: (event) ->
      if event
        event.preventDefault()
        ## ドロップダウンリストが閉じるのを防止
        event.stopPropagation()
      @$(".more-pages").html('<div class="loading-animation" tabindex=0><span class="sr" role="alert">' + gettext('Loading more threads') + '</span></div>')
      @$(".more-pages").addClass("loading")
      loadingDiv = @$(".more-pages .loading-animation")
      DiscussionUtil.makeFocusTrap(loadingDiv)
      loadingDiv.focus()
      options = {}
      switch @mode
        when 'search'
          options.search_text = @current_search
          if @group_id
            options.group_id = @group_id          
        when 'followed'
          options.user_id = window.user.id
          options.group_id = "all"
        when 'commentables'
          options.commentable_ids = @discussionIds
          if @group_id
            options.group_id = @group_id
        when 'all'
          if @group_id
            options.group_id = @group_id
        
    
      lastThread = @collection.last()?.get('id')
      if lastThread
        # Pagination; focus the first thread after what was previously the last thread
        @once("threads:rendered", ->
          $(".post-list li:has(a[data-id='#{lastThread}']) + li a").focus()
        )
      else
        # Totally refreshing the list (e.g. from clicking a sort button); focus the first thread
        @once("threads:rendered", ->
          $(".post-list a").first()?.focus()
        )

      error = =>
        @renderThreads()
        DiscussionUtil.discussionAlert(gettext("Sorry"), gettext("We had some trouble loading more threads. Please try again."))

      @collection.retrieveAnotherPage(@mode, options, {sort_key: @sortBy}, error)

    renderThread: (thread) =>
      content = $(_.template($("#thread-list-item-template").html())(thread.toJSON()))
      if thread.get('subscribed')
        content.addClass("followed")
      if thread.get('endorsed')
        content.addClass("resolved")
      if thread.get('read')
        content.addClass("read")
      unreadCount = thread.get('unread_comments_count')
      if unreadCount > 0
        content.find('.comments-count').addClass("unread").attr(
          "data-tooltip",
          interpolate(
            ngettext('%(unread_count)s new comment', '%(unread_count)s new comments', unreadCount),
            {unread_count: thread.get('unread_comments_count')},
            true
          )
        )
      @highlight(content)


    highlight: (el) ->
      el.html(el.html().replace(/&lt;mark&gt;/g, "<mark>").replace(/&lt;\/mark&gt;/g, "</mark>"))

    renderThreadListItem: (thread) =>
      view = new ThreadListItemView(model: thread)
      view.on "thread:selected", @threadSelected
      view.on "thread:removed", @threadRemoved
      view.render()
      @$(".post-list").append(view.el)

    threadSelected: (e) =>
      # Use .attr('data-id') rather than .data('id') because .data does type
      # coercion. Usually, this is fine, but when Mongo gives an object id with
      # no letters, it casts it to a Number.

      thread_id = $(e.target).closest("a").attr("data-id")
      @setActiveThread(thread_id)
      @trigger("thread:selected", thread_id)  # This triggers a callback in the DiscussionRouter which calls the line above...
      ## ドロップダウン閉じる
      @hideTopicDrop($("#browse-topic-list"))
      false

    threadRemoved: (thread_id) =>
      @trigger("thread:removed", thread_id)

    setActiveThread: (thread_id) ->
      @$(".post-list a[data-id!='#{thread_id}']").removeClass("active")
      ##@$(".post-list a[data-id='#{thread_id}']").addClass("active")
      target = @$(".post-list a[data-id='#{thread_id}']")
      target.addClass("active")
      $(".current-thread").html(target.children("span.title").html())



    showSearch: ->
        ## Search場所移動につき以下は不要 
##      @$(".browse").removeClass('is-dropped')
##      @hideTopicDrop()
##      @$(".search").addClass('is-open')
##      @$(".browse").removeClass('is-open')
      setTimeout (-> @$(".post-search-field").focus()), 200 unless @$(".post-search-field").is(":focus")

    goHome: ->
      @template = _.template($("#discussion-home").html())
      @hideTopicDrop($("#browse-topic-filter-dropdown"))
      $(".discussion-column").html(@template)
      $(".post-list a").removeClass("active")
      $("input.email-setting").bind "click", @updateEmailNotifications
      url = DiscussionUtil.urlFor("notifications_status",window.user.get("id"))
      DiscussionUtil.safeAjax
          url: url
          type: "GET"
          success: (response, textStatus) =>
            if response.status
              $('input.email-setting').attr('checked','checked')
            else
              $('input.email-setting').removeAttr('checked')
      thread_id = null
      @trigger("thread:removed")  
      #select all threads


    ## トピックドロップダウンの開閉。
    ## 部品としてfoundationのsplitボタンを利用
    toggleTopicDrop: (event) =>
      event.preventDefault()
      event.stopPropagation()
      ## ドロップダウン開閉で検索結果を消さない
      ## if @current_search != ""
      ##   @clearSearch()
      ## 検索ボタンやホームボタンは別の場所に移したので不要
      ## @$(".search").removeClass('is-open')
      ## @$(".browse").addClass('is-open')
      ## @$ (".browse").toggleClass('is-dropped')

      ## large表示とsmall表示のどちらのボタンか判定して開閉
      if event.data && event.data.dst
        if $(event.target).closest(".f-dropdown").length > 0
          return false
        else
          target = $('#'+event.data.dst)
      else
        target_name = $(event.target).attr('data-dropdown')
        target = $(event.target).closest(".browse").siblings("#"+target_name)
      target.toggleClass('open')

      ## 開閉はis-dropではなくopenで管理。
      ## foundationのsplitによるドロップダウンはhide時は画面左外に隠れている 
      if target.hasClass('open')
        target.css({left:'0px'})
##        @$(".browse-topic-drop-menu-wrapper").show()
##        $(".browse-topic-drop-search-input").focus()
        $("body").bind "click", @toggleTopicDrop
        $("body").bind "click", {dst:target_name}, @toggleTopicDrop
        $("body").bind "keydown", @setActiveItem
      else
        @hideTopicDrop(target)

    hideTopicDrop: (el) ->
##      @$(".browse-topic-drop-menu-wrapper").hide()
      el.css({left:'-9999px'})
      el.removeClass('open')
      $("body").unbind "click", @toggleTopicDrop
      $("body").unbind "keydown", @setActiveItem

    # TODO get rid of this asap
    setTopicHack: (boardNameContainer) ->
      item = $(boardNameContainer).closest('a')
      boardName = item.find(".board-name").html()
      ## 板名の見せ方を少し変更
      ##  _.each item.parents('ul').not('.browse-topic-drop-menu'), (parent) ->
      ##    boardName = $(parent).siblings('a').find('.board-name').html() + ' / ' + boardName
      _.each item.parents('div.content'), (parent) ->
        category = $(parent).siblings('a').find('.board-name')
        if category
          boardName = category.html() + ' <br> > ' + boardName
      @$(".current-board").html(@fitName(boardName))

    setTopic: (event) ->
      item = $(event.target).closest('a')
      boardName = item.find(".board-name").html()
      ## 板名の見せ方を少し変更
      ##  _.each item.parents('ul').not('.browse-topic-drop-menu'), (parent) ->
      ##    boardName = $(parent).siblings('a').find('.board-name').html() + ' / ' + boardName
      _.each item.parents('div.content'), (parent) ->
        category = $(parent).siblings('a').find('.board-name')
        if category
          boardName = category.html() + ' <br> > ' + boardName
      @$(".current-board").html(@fitName(boardName))

    setSelectedTopic: (name) ->
      @$(".current-board").html(@fitName(name))

    getNameWidth: (name) ->
      test = $("<div>")
      test.css
        "font-size": @$(".current-board").css('font-size')
        opacity: 0
        position: 'absolute'
        left: -1000
        top: -1000
      $("body").append(test)
      test.html(name)
      width = test.width()
      test.remove()
      return width

    fitName: (name) ->
      ## トピック名の長さを調整する関数
      ## あまり要らなさそうなのでOFFにする
      ## @maxNameWidth = (@$el.width() * .8) - 50
      ## width = @getNameWidth(name)
      ## if width < @maxNameWidth
      ##   return name
      ## path = (x.replace /^\s+|\s+$/g, "" for x in name.split("/"))
      ## while path.length > 1
      ##   path.shift()
      ##   partialName = gettext("…") + "/" + path.join("/")
      ##   if  @getNameWidth(partialName) < @maxNameWidth
      ##     return partialName
      ## rawName = path[0]
      ## name = gettext("…") + "/" + rawName
      ## while @getNameWidth(name) > @maxNameWidth
      ##   rawName = rawName[0...rawName.length-1]
      ##   name =  gettext("…") + "/" + rawName + gettext("…")
      return name


    toggleAccordion: (event) ->
      ## トピックのアコーディオン表示のために追加。
      if($(event.target).hasClass("board-name"))
        target = $(event.target).parent()
      else
        target = $(event.target)
      target.toggleClass("active")
      target.siblings("div.content").toggleClass("active")
      event.preventDefault()
      event.stopPropagation()

    filterTopic: (event) ->
      ## トピック選択時、ドロップダウンを閉じる
      @hideTopicDrop($("#browse-topic-filter-dropdown"))
      if @current_search != ""
        @setTopic(event)
        @clearSearch @filterTopic, event
      else
        @setTopic(event)  # just sets the title for the dropdown
        item = $(event.target).closest('dd')
        discussionId = item.find("span.board-name").data("discussion_id")
        if discussionId == "#all"
          @discussionIds = ""
          @$(".post-search-field").val("")
          @$('.cohort').show()                    
          @retrieveAllThreads()
        else if discussionId == "#flagged"
          @discussionIds = ""
          @$(".post-search-field").val("")
          @$('.cohort').hide() 
          @retrieveFlaggedThreads() 
        else if discussionId == "#following"
          @retrieveFollowed(event)
          @$('.cohort').hide()
        else
          discussionIds = _.map item.find(".board-name[data-discussion_id]"), (board) -> $(board).data("discussion_id").id
          
          if $(event.target).attr('cohorted') == "True"
            @retrieveDiscussions(discussionIds, "function(){$('.cohort').show();}")
          else
            @retrieveDiscussions(discussionIds, "function(){$('.cohort').hide();}")
    
    chooseCohort: (event) ->
      @group_id = @$('.cohort-options :selected').val()
      @collection.current_page = 0
      @collection.reset()
      @loadMorePages(event)
      
    retrieveDiscussion: (discussion_id, callback=null) ->
      url = DiscussionUtil.urlFor("retrieve_discussion", discussion_id)
      DiscussionUtil.safeAjax
        url: url
        type: "GET"
        success: (response, textStatus) =>
          @collection.current_page = response.page
          @collection.pages = response.num_pages
          @collection.reset(response.discussion_data)
          Content.loadContentInfos(response.annotated_content_info)
          @displayedCollection.reset(@collection.models)# Don't think this is necessary because it's called on collection.reset
          if callback?
            callback()

    
    retrieveDiscussions: (discussion_ids) ->
      @discussionIds = discussion_ids.join(',')
      @mode = 'commentables'
      @retrieveFirstPage()

    retrieveAllThreads: () ->
      @mode = 'all'
      @retrieveFirstPage()

    retrieveFirstPage: (event)->
      @collection.current_page = 0
      @collection.reset()
      @loadMorePages(event)

    retrieveFlaggedThreads: (event)->
      @collection.current_page = 0
      @collection.reset()
      @mode = 'flagged'
      @loadMorePages(event)

    sortThreads: (event) ->
      ## foundationのテンプレに合わせて変更
      ## activeSort = @$(".sort-bar a[class='active']")
      activeSort = @$(".sort-bar dd[class='active']")
      activeSort.removeClass("active")
      activeSort.attr("aria-checked", "false")
      ##newSort = $(event.target)
      newSort = $(event.target).parent()
      newSort.addClass("active")
      newSort.attr("aria-checked", "true")
      ## @sortBy = newSort.data("sort")
      @sortBy = newSort.find("a").data("sort")
      
      @displayedCollection.comparator = switch @sortBy
        when 'date' then @displayedCollection.sortByDateRecentFirst
        when 'votes' then @displayedCollection.sortByVotes
        when 'comments' then @displayedCollection.sortByComments
      @retrieveFirstPage(event)

    performSearch: (event) ->
      if event.which == 13
        event.preventDefault()
        ## カテゴリをALLに戻す
        @setSelectedTopic($(".board-name").first().text())
        ## 検索窓が2か所になったので
        ## text = @$(".post-search-field").val()
        text = @$(event.target).val()
        @searchFor(text)

    searchFor: (text, callback, value) ->
      @mode = 'search'
      @current_search = text
      url = DiscussionUtil.urlFor("search")
      #TODO: This might be better done by setting discussion.current_page=0 and calling discussion.loadMorePages
      # Mainly because this currently does not reset any pagination variables which could cause problems.
      # This doesn't use pagination either.
      DiscussionUtil.safeAjax
        $elem: @$(".post-search-field")
        data: { text: text }
        url: url
        type: "GET"
        $loading: $
        loadingCallback: =>
          @$(".post-list").html('<li class="loading"><div class="loading-animation"><span class="sr">' + gettext('Loading thread list') + '</span></div></li>')
        loadedCallback: =>
          if callback             
            callback 
        ##     callback.apply @, [value]
        success: (response, textStatus) =>
          if textStatus == 'success'
            # TODO: Augment existing collection?
            @collection.reset(response.discussion_data)
            Content.loadContentInfos(response.annotated_content_info)
            @collection.current_page = response.page
            @collection.pages = response.num_pages
            # TODO: Perhaps reload user info so that votes can be updated.
            # In the future we might not load all of a user's votes at once
            # so this would probably be necessary anyway
            @displayedCollection.reset(@collection.models) # Don't think this is necessary
            @collection.current_page = 0
            @$(".post-search-field").removeAttr("disabled")
            @loadMorePages(event)

	    
    clearSearch: (callback, value) ->
      @$(".post-search-field").val("")
      @searchFor("", callback, value)
      

    setActiveItem: (event) ->
      if event.which == 13
        $(".browse-topic-drop-menu-wrapper .focused").click()
        return
      if event.which != 40 && event.which != 38
        return

      event.preventDefault()

      items = $.makeArray($(".browse-topic-drop-menu-wrapper a").not(".hidden"))
      index = items.indexOf($('.browse-topic-drop-menu-wrapper .focused')[0])

      if event.which == 40
          index = Math.min(index + 1, items.length - 1)
      if event.which == 38
          index = Math.max(index - 1, 0)

      $(".browse-topic-drop-menu-wrapper .focused").removeClass("focused")
      $(items[index]).addClass("focused")

      itemTop = $(items[index]).parent().offset().top
      scrollTop = $(".browse-topic-drop-menu").scrollTop()
      itemFromTop = $(".browse-topic-drop-menu").offset().top - itemTop
      scrollTarget = Math.min(scrollTop - itemFromTop, scrollTop)
      scrollTarget = Math.max(scrollTop - itemFromTop - $(".browse-topic-drop-menu").height() + $(items[index]).height(), scrollTarget)
      $(".browse-topic-drop-menu").scrollTop(scrollTarget)

    retrieveFollowed: (event)=>
      @mode = 'followed'
      @retrieveFirstPage(event)

    updateEmailNotifications: () =>
      if $('input.email-setting').attr('checked')
        DiscussionUtil.safeAjax
          url: DiscussionUtil.urlFor("enable_notifications")
          type: "POST"
          error: () =>
            $('input.email-setting').removeAttr('checked')
      else
        DiscussionUtil.safeAjax
          url: DiscussionUtil.urlFor("disable_notifications")
          type: "POST"
          error: () =>
            $('input.email-setting').attr('checked','checked')


