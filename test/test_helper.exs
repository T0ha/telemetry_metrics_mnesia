:mnesia.stop()
{:ok, _} = Node.start(:"test@127.0.0.1")
:mnesia.start()
ExUnit.start()
