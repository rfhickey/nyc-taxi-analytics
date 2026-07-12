"""Project domain types: DomainType subclasses and named refinements."""

from dblect import DomainType
from dblect.types import UnitEnum


class Currency(UnitEnum):
    USD = "USD"


class Money(DomainType):
    """A monetary amount in a single currency."""

    amount: float
    currency: Currency


# Everything in the TLC feed is charged in US dollars.
Usd = Money.refine(currency=Currency.USD)
