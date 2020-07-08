# TODO
# - create
# - update
# - delete
# - queries
# - count
# - find_one
# - find_many
# - update_many
# - delete_many
# - upsert
# - where, include, select
#
defmodule Prisma.Model do
  defmacro __using__(_opts) do
    quote do
      import Prisma.Model

      Module.register_attribute(__MODULE__, :table_name, persist: true)
      Module.register_attribute(__MODULE__, :fields, accumulate: true, persist: true)
      Module.register_attribute(__MODULE__, :relations, accumulate: true, persist: true)
    end
  end

  defmacro schema(name, do: block) do
    quote do
      @table_name unquote(name)

      unquote(block)

      def __table_name__, do: @table_name
      def __fields__, do: Enum.reverse(@fields)
      def __relations__, do: Enum.reverse(@relations)

      def find_one(opts) do
        where = Keyword.fetch!(opts, :where)

        operations = [
          {
            :select,
            table: __table_name__(),
            where: where
          }
        ]

        %{
          type: 'select',
          operations: operations,
          select: Keyword.get(opts, :select, nil) |> List.wrap(),
          include: Keyword.get(opts, :include, nil) |> List.wrap()
        }
      end

      def create(opts) do
        data = Keyword.fetch!(opts, :data)
        initial = %{table_name: __table_name__(), fields: [], belongs_tos: [], has_manys: []}

        plan = Enum.reduce(data, initial, fn {field, value}, acc ->
          cond do
            Enum.find(__fields__(), fn {name, _type} -> name == field end) ->
              %{acc | fields: [{field, value} | acc.fields]}

            relation = Enum.find(__relations__(), fn {relationship, name, _association} -> name == field && relationship == :has_many end) ->
              {_type, _name, related} = relation
              %{acc | has_manys: [{field, related.__table_name__(), value} | acc.has_manys]}

            relation = Enum.find(__relations__(), fn {relationship, name, _association} -> name == field && relationship == :belongs_to end) ->
              {_type, _name, related} = relation
              %{acc | belongs_tos: [{field, related.__table_name__(), value} | acc.has_manys]}

            true ->
              raise ArgumentError, message: "Unknown field `#{field}`"
          end
        end)

        operations = [{:insert, table: plan.table_name, fields: plan.fields}]
        operations = operations ++ Enum.map(plan.belongs_tos, fn {_name, table, creates} ->
          Enum.map(creates, fn {:create, fields} ->
            {:insert, table: table, fields: [{"#{plan.table_name}_id", "$id"} | Enum.to_list(fields)]}
          end)
        end)
        operations = operations ++ Enum.map(plan.has_manys, fn {_name, table, creates} ->
          Enum.map(creates, fn {:create, fields} ->
            {:insert, table: table, fields: [{"#{plan.table_name}_id", "$id"} | Enum.to_list(fields)]}
          end)
        end) |> List.flatten()


        %{
          type: 'create',
          operations: operations,
          select: Keyword.get(opts, :select, nil) |> List.wrap(),
          include: Keyword.get(opts, :include, nil) |> List.wrap()
        }
      end

      def delete(opts) do
        where = Keyword.fetch!(opts, :where)

        operations = [
          {
            :delete,
            table: __table_name__(),
            where: where
          }
        ]

        %{
          type: 'delete',
          operations: operations,
          select: Keyword.get(opts, :select, nil) |> List.wrap(),
          include: Keyword.get(opts, :include, nil) |> List.wrap()
        }
      end
    end
  end

  defmacro has_many(name, relation) do
    quote do
      @relations {:has_many, unquote(name), unquote(relation)}
    end
  end

  defmacro belongs_to(name, relation) do
    quote do
      @relations {:belongs_to, unquote(name), unquote(relation)}
    end
  end

  defmacro field(name, type \\ :string) do
    quote do
      @fields {unquote(name), unquote(type)}
    end
  end
end

defmodule Company do
  use Prisma.Model

  schema "companies" do
    has_many :contacts, Contact

    field :name, :string
    field :industry, :string
  end
end

defmodule Contact do
  use Prisma.Model

  schema("contacts") do
    belongs_to :company, Company 

    field :name, :string
    field :email, :string
    field :phone, :string
    field :primary, :boolean
  end
end

Company.create(
  data: %{
    name: "ACME",
    industry: "Geology",
    contacts: [
      create: %{ name: "John Smith", phone: "123-213-1234" },
      create: %{ name: "Jane Smith", phone: "123-213-1233" }
    ]
  }
) |> IO.inspect(label: "Company")

Contact.create(
  data: %{
    name: "John Smith",
    phone: "123-123-1234",
    company: %{
      create: %{ name: "ACME", industry: "Geology" },
    }
  }
) |> IO.inspect(label: "Contact")

Contact.delete(where: [id: 1], include: :company, select: :name) |> IO.inspect

Contact.find_one(where: [id: 1]) |> IO.inspect
