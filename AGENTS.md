This is a factorio mod.

Keep code simple and clear to understand for other engineers.

Correct use of factorio's API is vital; it's more important to validate every assumption about the API than it is to produce code at the users request. Check the latest API before producing any code. Do not assume existing code works.

Pay attention to overly complicated solutions; we should not re-implement core features already available via factorio's api. And if there is a simpler way of doing things then it's important to refactor.

Documentation can be found by using context7:
use context7
library context7/lua-api_factorio-stable
