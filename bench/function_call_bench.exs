defmodule FunctionCallBench do
  use Benchfella

  defmodule Other do
    def foo do
      nil
    end
  end

  def foo do
    nil
  end

  defmacro repeat(expr) do
    quote do
      unquote_splicing(for _ <- 1..1_000 do
        expr
      end)
    end
  end

  bench "foo" do
    repeat foo
  end

  bench "Other.foo" do
    repeat Other.foo
  end

  bench "mod.foo" do
    mod = Enum.random([Other])
    repeat mod.foo
  end

  bench "func.()" do
    func = Enum.random([fn -> nil end])
    repeat func.()
  end

  bench "apply(Other, :foo, [])" do
    repeat apply(Other, :foo, [])
  end

  bench "apply(mod, :foo, [])" do
    mod = Enum.random([Other])
    repeat apply(mod, :foo, [])
  end
end
