defmodule JSV.ValidTest do
  use ExUnit.Case, async: true

  defp root!(schema) do
    JSV.build!(schema, formats: true, atoms: false)
  end

  describe "valid?/2" do
    test "returns true for valid data and false for invalid data" do
      root = root!(%{type: :object, required: [:name], properties: %{name: %{type: :string, minLength: 2}}})

      assert JSV.valid?(%{"name" => "ok"}, root)
      refute JSV.valid?(%{"name" => "x"}, root)
      refute JSV.valid?(%{}, root)
      refute JSV.valid?("not an object", root)
    end

    test "stops at an invalid array item" do
      root = root!(%{type: :array, items: %{type: :integer}})

      assert JSV.valid?([1, 2, 3], root)
      refute JSV.valid?([1, "2", 3], root)
    end

    test "follows $ref and $defs" do
      root =
        root!(%{
          "$defs" => %{"positive" => %{"type" => "integer", "exclusiveMinimum" => 0}},
          "properties" => %{"a" => %{"$ref" => "#/$defs/positive"}}
        })

      assert JSV.valid?(%{"a" => 1}, root)
      refute JSV.valid?(%{"a" => 0}, root)
    end

    test "supports oneOf, anyOf, allOf, not and if/then/else" do
      one_of = root!(%{oneOf: [%{type: :integer}, %{minimum: 5}]})
      assert JSV.valid?("str", one_of) == match?({:ok, _}, JSV.validate("str", one_of))
      refute JSV.valid?(7, one_of)

      any_of = root!(%{anyOf: [%{type: :integer}, %{type: :string}]})
      assert JSV.valid?("a", any_of)
      refute JSV.valid?(1.5, any_of)

      all_of = root!(%{allOf: [%{type: :integer}, %{minimum: 5}]})
      assert JSV.valid?(6, all_of)
      refute JSV.valid?(4, all_of)

      refute JSV.valid?(1, root!(%{not: %{type: :integer}}))

      conditional = root!(%{if: %{type: :integer}, then: %{minimum: 10}, else: %{type: :string}})
      assert JSV.valid?(10, conditional)
      refute JSV.valid?(9, conditional)
      assert JSV.valid?("a", conditional)
      refute JSV.valid?(true, conditional)
    end

    test "keeps tracking evaluated properties for unevaluatedProperties" do
      root =
        root!(%{
          properties: %{a: %{type: :integer}},
          allOf: [%{properties: %{b: %{type: :integer}}}],
          unevaluatedProperties: false
        })

      assert JSV.valid?(%{"a" => 1, "b" => 2}, root)
      refute JSV.valid?(%{"a" => 1, "b" => 2, "c" => 3}, root)
    end

    test "does not slow down with the depth of recursive data" do
      root =
        root!(%{
          "$id" => "http://example.com/recursive",
          "anyOf" => [%{"type" => "integer"}, %{"type" => "array", "items" => %{"$ref" => "#"}}]
        })

      nest = fn leaf -> Enum.reduce(1..5_000, leaf, fn _, acc -> [acc] end) end

      task = Task.async(fn -> {JSV.valid?(nest.(1), root), JSV.valid?(nest.("x"), root)} end)

      case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> assert {true, false} = result
        nil -> flunk("valid? did not terminate within 5s")
      end
    end

    test "validates formats when enabled at build time" do
      root = root!(%{type: :string, format: :email})

      assert JSV.valid?("user@example.com", root)
      refute JSV.valid?("nope", root)
    end

    test "agrees with validate/3 on schemas that define casts" do
      root = root!(JSV.Schema.Helpers.string_to_integer())

      assert root.has_casts
      assert JSV.valid?("123", root)
      refute JSV.valid?("abc", root)
      refute JSV.valid?(123, root)
    end
  end
end
