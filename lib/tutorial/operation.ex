defmodule(Tutorial.Operation) do
  @moduledoc("Auto-generated Thrift enum tutorial.Operation")
  defmacro(add) do
    1
  end
  defmacro(subtract) do
    2
  end
  defmacro(multiply) do
    3
  end
  defmacro(divide) do
    4
  end
  def(member?(1)) do
    true
  end
  def(member?(2)) do
    true
  end
  def(member?(3)) do
    true
  end
  def(member?(4)) do
    true
  end
  def(member?(_)) do
    false
  end
end