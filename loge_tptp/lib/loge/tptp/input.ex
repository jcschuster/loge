defimpl Loge.Input, for: Tptp.File do
  def to_iodata(file), do: AtpClient.Input.to_iodata(file)
  def language(_file), do: :tptp
end

defimpl Loge.Input, for: Tptp.Unit do
  def to_iodata(unit), do: AtpClient.Input.to_iodata(unit)
  def language(_unit), do: :tptp
end
