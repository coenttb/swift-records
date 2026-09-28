import ISO_9075_Foundation
import PostgreSQL
import SQL
import SQL_Macros
import Testing

@Suite struct `Math functions` {
    let measurement = MathFixtures.Measurement.columns
    let number = MathFixtures.Number.columns

    @Test func `constants and randomness take no arguments`() {
        #expect(PostgreSQL().render(PostgreSQL.Math.pi().queryFragment).sql == "pi()")
        #expect(PostgreSQL().render(PostgreSQL.Math.random().queryFragment).sql == "random()")
        #expect(PostgreSQL().render(PostgreSQL.Math.setseed(0.5).queryFragment) == ISO_9075.Rendering(
            sql: "setseed($1)",
            values: [.double(0.5)]
        ))
    }

    @Test func `rounding functions wrap the expression`() {
        #expect(PostgreSQL().render(measurement.value.ceil().queryFragment).sql == #"ceil("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.ceiling().queryFragment).sql == #"ceiling("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.floor().queryFragment).sql == #"floor("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.trunc().queryFragment).sql == #"trunc("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.sign().queryFragment).sql == #"sign("measurements"."value")"#)
    }

    @Test func `truncation inlines its decimal places`() {
        let rendering = PostgreSQL().render(measurement.value.trunc(decimalPlaces: 2).queryFragment)
        #expect(rendering == ISO_9075.Rendering(sql: #"trunc("measurements"."value", 2)"#, values: []))
    }

    @Test func `integer division binds a value divisor`() {
        let rendering = PostgreSQL().render(number.value.div(10).queryFragment)
        #expect(rendering == ISO_9075.Rendering(sql: #"div("numbers"."value", $1)"#, values: [.int(10)]))
    }

    @Test func `number theory functions take two expressions`() {
        #expect(PostgreSQL().render(number.value.gcd(number.divisor).queryFragment).sql
            == #"gcd("numbers"."value", "numbers"."divisor")"#)
        #expect(PostgreSQL().render(number.value.lcm(number.divisor).queryFragment).sql
            == #"lcm("numbers"."value", "numbers"."divisor")"#)
        #expect(PostgreSQL().render(number.value.factorial().queryFragment).sql == #"factorial("numbers"."value")"#)
    }

    @Test func `exponential functions render their names`() {
        #expect(PostgreSQL().render(measurement.value.power(2.0).queryFragment) == ISO_9075.Rendering(
            sql: #"power("measurements"."value", $1)"#,
            values: [.double(2)]
        ))
        #expect(PostgreSQL().render(measurement.value.sqrt().queryFragment).sql == #"sqrt("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.cbrt().queryFragment).sql == #"cbrt("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.exp().queryFragment).sql == #"exp("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.ln().queryFragment).sql == #"ln("measurements"."value")"#)
        #expect(PostgreSQL().render(measurement.value.log10().queryFragment).sql == #"log("measurements"."value")"#)
    }

    @Test func `a logarithm binds its base first`() {
        let rendering = PostgreSQL().render(measurement.value.log(base: 2.0).queryFragment)
        #expect(rendering == ISO_9075.Rendering(sql: #"log($1, "measurements"."value")"#, values: [.double(2)]))
    }

    @Test func `trigonometric functions render their names`() {
        #expect(PostgreSQL().render(measurement.angle.sin().queryFragment).sql == #"sin("measurements"."angle")"#)
        #expect(PostgreSQL().render(measurement.angle.acosh().queryFragment).sql == #"acosh("measurements"."angle")"#)
        #expect(PostgreSQL().render(measurement.angle.degrees().queryFragment).sql == #"degrees("measurements"."angle")"#)
        #expect(PostgreSQL().render(measurement.angle.atan2(measurement.value).queryFragment).sql
            == #"atan2("measurements"."angle", "measurements"."value")"#)
    }
}
