defmodule Phoenix.LiveAdmin.Components.Resource.Index do
  use Phoenix.LiveComponent
  use Phoenix.HTML

  import Phoenix.LiveAdmin.Components.Resource,
    only: [repo: 0, fields: 2, route_with_params: 3, get_resource!: 3]

  import Phoenix.LiveAdmin,
    only: [associated_resource: 3, record_label: 2, get_config: 2, parent_associations: 1]

  import Ecto.Query

  alias Phoenix.LiveAdmin.SessionStore

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        records:
          list(
            assigns.resource,
            assigns.config,
            Map.take(assigns, [:prefix, :sort, :page, :search])
          ),
        sort_attr: elem(assigns.sort, 1),
        sort_dir: elem(assigns.sort, 0)
      )

    ~H"""
    <div class="resource__list">
      <div class="list__search">
        <div class="flex border-2 rounded-lg">
            <form phx-change="search" phx-target={@myself}>
              <input
                type="text"
                class="px-4 py-1 w-60 border-0 h-8"
                placeholder="Search..."
                name="query"
                onkeydown="return event.key != 'Enter'"
                value={@search}
                phx-debounce="500"
              />
            </form>
            <button phx-click="search" phx-value-query="" class="flex items-center justify-center px-2 border-l">
              <svg class="w-6 h-6 text-gray-600" fill="currentColor" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                <path d="M16.32 14.9l5.39 5.4a1 1 0 0 1-1.42 1.4l-5.38-5.38a8 8 0 1 1 1.41-1.41zM10 16a6 6 0 1 0 0-12 6 6 0 0 0 0 12z" />
              </svg>
            </button>
        </div>
      </div>
      <table class="resource__table">
        <thead>
          <tr>
            <%= for {field, _, _} <- fields(@resource, @config) do %>
              <th class="resource__header" title={field}>
                <%= list_link @socket, humanize(field), @key, %{prefix: @prefix, page: @page, "sort-attr": field, "sort-dir": (if field == @sort_attr, do: Enum.find([:asc, :desc], & &1 != @sort_dir), else: @sort_dir)}, class: "header__link#{if field == @sort_attr, do: "--#{[asc: :down, desc: :up][@sort_dir]}"}" %>
              </th>
            <% end %>
            <th class="resource__header">Actions</th>
          </tr>
        </thead>
        <tbody>
          <%= for record <- @records |> elem(0) do %>
            <tr>
              <%= for {field, _, _} <- fields(@resource, @config) do %>
                <td class="resource__cell">
                  <div class="cell__contents">
                    <%= display_field(record, field, assigns) %>
                  </div>
                </td>
              <% end %>
              <td class="resource__cell">
                <%= live_redirect "Edit", to: route_with_params(@socket, [:edit, @key, record.id], prefix: @prefix), class: "resource__action--btn" %>
                <%= link "Delete", to: "#", "data-confirm": "Are you sure?", "phx-click": "delete", "phx-value-id": record.id, "phx-target": @myself, class: "resource__action--btn" %>
                <%= for action <- Map.get(@config, :actions, []) do %>
                  <%= link action |> to_string() |> humanize(), to: "#", "data-confirm": "Are you sure?", "phx-click": "action", "phx-value-id": record.id, "phx-value-action": action, "phx-target": @myself, class: "resource__action--btn" %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr>
            <td class="w-full" colspan={@resource |> fields(@config) |> Enum.count()}>
              <%= if @page > 1, do: list_link(@socket, "Prev", @key, %{prefix: @prefix, page: @page - 1, "sort-attr": @sort_attr, "sort-dir": @sort_dir, search: @search}, class: "resource__action--btn"), else: content_tag(:span, "Prev", class: "resource__action--disabled") %>
              <%= if @page < (@records |> elem(1)) / 10, do: list_link(@socket, "Next", @key, %{prefix: @prefix, page: @page + 1, "sort-attr": @sort_attr, "sort-dir": @sort_dir, search: @search}, class: "resource__action--btn"), else: content_tag(:span, "Next", class: "resource__action--disabled") %>
            </td>
            <td class="text-right p-2"><%= @records |> elem(1) %> total rows</td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  @impl true
  def handle_event(
        "delete",
        %{"id" => id},
        %{
          assigns: %{
            resource: resource,
            key: key,
            config: config,
            session_id: session_id,
            page: page
          }
        } = socket
      ) do
    socket =
      id
      |> get_resource!(resource, socket.assigns.prefix)
      |> delete_resource(config, SessionStore.lookup(session_id))
      |> case do
        {:ok, _} ->
          socket
          |> put_flash(:info, "Deleted #{resource}")
          |> push_redirect(to: route_with_params(socket, [:list, key], page: page))

        {:error, _} ->
          put_flash(socket, :error, "Could not delete #{resource}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("action", %{"action" => action, "id" => id}, socket) do
    record = get_resource!(id, socket.assigns.resource, socket.assigns.prefix)

    action_name = String.to_existing_atom(action)

    session = SessionStore.lookup(socket.assigns.session_id)

    {m, f, a} =
      socket.assigns
      |> get_in([:config, :actions, action_name])
      |> case do
        nil -> {socket.assigns.resource, action_name, []}
        tuple when tuple_size(tuple) == 3 -> tuple
      end

    socket =
      case apply(m, f, [record, session] ++ a) do
        {:ok, result} ->
          socket
          |> put_flash(:info, "Successfully completed #{action}: #{inspect(result)}")
          |> push_redirect(
            to:
              route_with_params(
                socket,
                [:list, socket.assigns.key],
                Map.take(socket.assigns, [:prefix, :page])
              )
          )

        {:error, error} ->
          put_flash(socket, :error, "#{action} failed: #{error}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    params = %{
      page: socket.assigns.page,
      "sort-attr": elem(socket.assigns.sort, 1),
      "sort-dir": elem(socket.assigns.sort, 0),
      s: query,
      prefix: socket.assigns.prefix
    }

    socket =
      push_patch(socket, to: route_with_params(socket, [:list, socket.assigns.key], params))

    {:noreply, socket}
  end

  def display_field(record = %resource{}, field_name, assigns) do
    field_val = Map.fetch!(record, field_name)

    with field_val when not is_nil(field_val) <- field_val,
         {key, {_, config}} <- associated_resource(resource, field_name, assigns.resources),
         assoc_name when not is_nil(assoc_name) <-
           Enum.find(resource.__schema__(:associations), fn assoc_name ->
             case resource.__schema__(:association, assoc_name) do
               %{owner_key: ^field_name, relationship: :parent} -> assoc_name
               _ -> nil
             end
           end) do
      record
      |> repo().preload(assoc_name)
      |> Map.fetch!(assoc_name)
      |> record_label(config)
      |> live_redirect(
        to: route_with_params(assigns.socket, [:edit, key, field_val], prefix: assigns.prefix),
        class: "resource__action--btn"
      )
    else
      _ -> inspect(field_val)
    end
  end

  def list_link(socket, content, key, params, opts \\ []),
    do:
      live_patch(content, Keyword.put(opts, :to, route_with_params(socket, [:list, key], params)))

  def list(resource, config, opts) do
    opts =
      opts
      |> Enum.into(%{})
      |> Map.put_new(:page, 1)
      |> Map.put_new(:sort, {:asc, :id})

    query =
      resource
      |> limit(10)
      |> offset(^((opts[:page] - 1) * 10))
      |> order_by(^[opts[:sort]])
      |> preload(^preloads_for_resource(resource, config))

    query =
      opts
      |> Enum.reduce(query, fn
        {:search, q}, query when byte_size(q) > 0 ->
          apply_search(query, q, fields(resource, config))

        _, query ->
          query
      end)

    {
      repo().all(query, prefix: opts[:prefix]),
      repo().aggregate(query |> exclude(:limit) |> exclude(:offset), :count, prefix: opts[:prefix])
    }
  end

  defp delete_resource(record, config, session) do
    config
    |> get_config(:delete_with)
    |> case do
      nil ->
        repo().delete(record)

      {mod, func_name, args} ->
        apply(mod, func_name, [record, session] ++ args)
    end
  end

  defp apply_search(query, q, fields) do
    q
    |> String.split(~r{[^\s]*:}, include_captures: true, trim: true)
    |> case do
      [q] ->
        Enum.reduce(fields, query, fn {field_name, _, _}, query ->
          or_where(
            query,
            [r],
            ilike(fragment("CAST(? AS text)", field(r, ^field_name)), ^"%#{q}%")
          )
        end)

      field_queries ->
        field_queries
        |> Enum.map(&String.trim/1)
        |> Enum.chunk_every(2)
        |> Enum.reduce(query, fn
          [field_key, q], query ->
            if {field_name, _, _} =
                 Enum.find(fields, fn {field_name, _, _} -> "#{field_name}:" == field_key end) do
              or_where(
                query,
                [r],
                ilike(fragment("CAST(? AS text)", field(r, ^field_name)), ^"%#{q}%")
              )
            else
              query
            end

          [_], query ->
            query
        end)
    end
  end

  defp preloads_for_resource(resource, config) do
    config
    |> Map.get(:preload)
    |> case do
      nil -> resource |> parent_associations() |> Enum.map(& &1.field)
      {m, f, a} -> apply(m, f, [resource | a])
      preloads when is_list(preloads) -> preloads
    end
  end
end
