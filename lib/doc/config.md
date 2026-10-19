# config

Read key = value files (eve.cfg, evedb.cfg, eve.env) into a DataMap: quoted text, whole numbers, true and false.
@spec spec/library/config.md  @feature F-TLS-12  @decision D-189  @tests test/level6/f08_config

## `function value_of(raw: String) => (@result: Any) is`

The Eve value of the text after the equal sign: "text" is a String, 42 an Integer, true and false a Logic.

## `function parse(text: String) => (@result: Any) is`

The settings of a text: one key = value for each line.

## `function read!(path: String) => (@result: Any) is`

The settings of a file; a missing file is the error $err_file.

## `function has(settings: Any, key: String) => (@result: Logic) is`

Is the key in the settings.

## `function get(:T)(settings: Any, key: String, default: T) => (@result: T) is`

The value of the key, or the default when the key is not there.

