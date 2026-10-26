# F-LNG-17 Stream type

`Stream(:T) <: Iterable(:T)`, read by `for` with back-pressure; at level 4 `Channel(:T)` is the stream, and lists get `batch(n)` and `split(k)`. Generators, files and queries adopt it at level 5, with `map`, `filter`, `merge`, `window`, `parallel(n)`.

*Partial:* `for` on a channel, `batch`, `split`.

## Missing

- Built in the library `data.stream` (generators over lists and generators): `map`, `filter`, `take`, `drop`, `chain`, `numbered`, `sliding`, `merge`. Not yet: `parallel(n)`, and the operators on the streams of files and queries.
- The level 4 part (`for` on a channel, `batch`, `split`) is done.
