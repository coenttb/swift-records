import ISO_9075_Foundation
import PostgreSQL
import SQL
import SQL_Macros
import Testing

@Suite struct `Window ranking functions` {
    let score = WindowFixtures.Score.columns

    @Test func `an empty specification renders an empty window`() {
        #expect(PostgreSQL().render(PostgreSQL.Window.rowNumber().queryFragment).sql == "ROW_NUMBER() OVER ()")
        #expect(PostgreSQL().render(PostgreSQL.Window.rowNumber().over().queryFragment).sql == "ROW_NUMBER() OVER ()")
    }

    @Test func `an ordering renders inside the window`() {
        let rendering = PostgreSQL().render(
            PostgreSQL.Window.rank().over { $0.order(by: score.points.desc()) }.queryFragment
        )
        #expect(rendering == ISO_9075.Rendering(
            sql: #"RANK() OVER (ORDER BY "scores"."points" DESC)"#,
            values: []
        ))
    }

    @Test func `a partition renders before the ordering`() {
        let rendering = PostgreSQL().render(
            PostgreSQL.Window.denseRank()
                .over { $0.partition(by: score.playerID).order(by: score.points.desc()) }
                .queryFragment
        )
        #expect(rendering.sql == #"DENSE_RANK() OVER (PARTITION BY "scores"."playerID" ORDER BY "scores"."points" DESC)"#)
    }

    @Test func `distribution functions render their names`() {
        #expect(
            PostgreSQL().render(PostgreSQL.Window.percentRank().over { $0.order(by: score.points) }.queryFragment).sql
                == #"PERCENT_RANK() OVER (ORDER BY "scores"."points")"#
        )
        #expect(
            PostgreSQL().render(PostgreSQL.Window.cumeDist().over { $0.order(by: score.points) }.queryFragment).sql
                == #"CUME_DIST() OVER (ORDER BY "scores"."points")"#
        )
    }

    @Test func `ntile inlines its bucket count`() {
        let rendering = PostgreSQL().render(
            PostgreSQL.Window.ntile(4).over { $0.order(by: score.points.asc()) }.queryFragment
        )
        #expect(rendering.sql == #"NTILE(4) OVER (ORDER BY "scores"."points" ASC)"#)
    }

    @Test func `a window function is selectable`() {
        let rendering = PostgreSQL().render(
            WindowFixtures.Score.select { ($0.id, PostgreSQL.Window.rowNumber().over()) }.query
        )
        #expect(rendering.sql == "SELECT \"scores\".\"id\", ROW_NUMBER() OVER ()\nFROM \"scores\"")
    }
}

@Suite struct `Window value functions` {
    let price = WindowFixtures.StockPrice.columns

    @Test func `lag inlines its offset`() {
        let rendering = PostgreSQL().render(
            price.price.lag().over { $0.order(by: price.day.asc()) }.queryFragment
        )
        #expect(rendering == ISO_9075.Rendering(
            sql: #"LAG("stock_prices"."price", 1) OVER (ORDER BY "stock_prices"."day" ASC)"#,
            values: []
        ))
    }

    @Test func `lag binds its default`() {
        let rendering = PostgreSQL().render(
            price.price.lag(offset: 2, default: 0.0).over { $0.order(by: price.day.asc()) }.queryFragment
        )
        #expect(rendering == ISO_9075.Rendering(
            sql: #"LAG("stock_prices"."price", 2, $1) OVER (ORDER BY "stock_prices"."day" ASC)"#,
            values: [.double(0.0)]
        ))
    }

    @Test func `lead renders its offset`() {
        let rendering = PostgreSQL().render(
            price.price.lead().over { $0.order(by: price.day.asc()) }.queryFragment
        )
        #expect(rendering.sql == #"LEAD("stock_prices"."price", 1) OVER (ORDER BY "stock_prices"."day" ASC)"#)
    }

    @Test func `first, last and nth values render their arguments`() {
        #expect(
            PostgreSQL().render(price.price.firstValue().over { $0.order(by: price.price.desc()) }.queryFragment).sql
                == #"FIRST_VALUE("stock_prices"."price") OVER (ORDER BY "stock_prices"."price" DESC)"#
        )
        #expect(
            PostgreSQL().render(
                price.price.lastValue()
                    .over { $0.partition(by: price.symbol).order(by: price.price.desc()) }
                    .queryFragment
            ).sql
                == #"LAST_VALUE("stock_prices"."price") OVER (PARTITION BY "stock_prices"."symbol" ORDER BY "stock_prices"."price" DESC)"#
        )
        #expect(
            PostgreSQL().render(price.price.nthValue(2).over { $0.order(by: price.price.desc()) }.queryFragment).sql
                == #"NTH_VALUE("stock_prices"."price", 2) OVER (ORDER BY "stock_prices"."price" DESC)"#
        )
    }
}

@Suite struct `Window frames` {
    let score = WindowFixtures.Score.columns

    @Test func `rows between two bounds`() {
        let rendering = PostgreSQL().render(
            PostgreSQL.Window.rowNumber()
                .over {
                    $0.partition(by: score.playerID)
                        .order(by: score.id)
                        .rows(between: .unboundedPreceding, and: .currentRow)
                }
                .queryFragment
        )
        #expect(rendering.sql == #"ROW_NUMBER() OVER (PARTITION BY "scores"."playerID" ORDER BY "scores"."id" ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)"#)
    }

    @Test func `offsets render before their direction`() {
        let rendering = PostgreSQL().render(
            PostgreSQL.Window.rank()
                .over { $0.order(by: score.id).rows(between: .preceding(2), and: .following(3)) }
                .queryFragment
        )
        #expect(rendering.sql == #"RANK() OVER (ORDER BY "scores"."id" ROWS BETWEEN 2 PRECEDING AND 3 FOLLOWING)"#)
    }

    @Test func `a single bound renders without between`() {
        let rendering = PostgreSQL().render(
            PostgreSQL.Window.rank().over { $0.order(by: score.id).rows(.preceding(5)) }.queryFragment
        )
        #expect(rendering.sql == #"RANK() OVER (ORDER BY "scores"."id" ROWS 5 PRECEDING)"#)
    }

    @Test func `range and groups frames render their unit`() {
        #expect(
            PostgreSQL().render(
                PostgreSQL.Window.rank()
                    .over { $0.order(by: score.id).range(between: .unboundedPreceding, and: .unboundedFollowing) }
                    .queryFragment
            ).sql
                == #"RANK() OVER (ORDER BY "scores"."id" RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)"#
        )
        #expect(
            PostgreSQL().render(
                PostgreSQL.Window.rank().over { $0.order(by: score.points).groups(.currentRow) }.queryFragment
            ).sql
                == #"RANK() OVER (ORDER BY "scores"."points" GROUPS CURRENT ROW)"#
        )
    }

    @Test func `a frame without ordering renders alone`() {
        let rendering = PostgreSQL().render(
            PostgreSQL.Window.rowNumber()
                .over { $0.framed(PostgreSQL.Window.Frame(.rows, from: .unboundedPreceding)) }
                .queryFragment
        )
        #expect(rendering.sql == "ROW_NUMBER() OVER (ROWS UNBOUNDED PRECEDING)")
    }
}
