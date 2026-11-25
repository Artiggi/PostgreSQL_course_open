-- DROP SCHEMA bookings;

CREATE SCHEMA bookings AUTHORIZATION postgres;

-- DROP SEQUENCE bookings.flights_flight_id_seq;

CREATE SEQUENCE bookings.flights_flight_id_seq
	INCREMENT BY 1
	MINVALUE 1
	MAXVALUE 2147483647
	START 1
	CACHE 1
	NO CYCLE;-- bookings.airplanes_data определение

-- Drop table

-- DROP TABLE bookings.airplanes_data;

CREATE TABLE bookings.airplanes_data (
	airplane_code bpchar(3) NOT NULL, -- Airplane code, IATA
	model jsonb NOT NULL, -- Airplane model
	"range" int4 NOT NULL, -- Maximum flight range, km
	speed int4 NOT NULL, -- Cruise speed, km/h
	CONSTRAINT airplanes_data_pkey PRIMARY KEY (airplane_code),
	CONSTRAINT airplanes_data_range_check CHECK ((range > 0)),
	CONSTRAINT airplanes_data_speed_check CHECK ((speed > 0))
);
COMMENT ON TABLE bookings.airplanes_data IS 'Airplanes (internal multilingual data)';

-- Column comments

COMMENT ON COLUMN bookings.airplanes_data.airplane_code IS 'Airplane code, IATA';
COMMENT ON COLUMN bookings.airplanes_data.model IS 'Airplane model';
COMMENT ON COLUMN bookings.airplanes_data."range" IS 'Maximum flight range, km';
COMMENT ON COLUMN bookings.airplanes_data.speed IS 'Cruise speed, km/h';


-- bookings.airports_data определение

-- Drop table

-- DROP TABLE bookings.airports_data;

CREATE TABLE bookings.airports_data (
	airport_code bpchar(3) NOT NULL, -- Airport code, IATA
	airport_name jsonb NOT NULL, -- Airport name
	city jsonb NOT NULL, -- City
	country jsonb NOT NULL, -- Country
	coordinates point NOT NULL, -- Airport coordinates (longitude and latitude)
	timezone text NOT NULL, -- Airport time zone
	CONSTRAINT airports_data_pkey PRIMARY KEY (airport_code)
);
COMMENT ON TABLE bookings.airports_data IS 'Airports (internal multilingual data)';

-- Column comments

COMMENT ON COLUMN bookings.airports_data.airport_code IS 'Airport code, IATA';
COMMENT ON COLUMN bookings.airports_data.airport_name IS 'Airport name';
COMMENT ON COLUMN bookings.airports_data.city IS 'City';
COMMENT ON COLUMN bookings.airports_data.country IS 'Country';
COMMENT ON COLUMN bookings.airports_data.coordinates IS 'Airport coordinates (longitude and latitude)';
COMMENT ON COLUMN bookings.airports_data.timezone IS 'Airport time zone';


-- bookings.bookings определение

-- Drop table

-- DROP TABLE bookings.bookings;

CREATE TABLE bookings.bookings (
	book_ref bpchar(6) NOT NULL, -- Booking number
	book_date timestamptz NOT NULL, -- Booking date
	total_amount numeric(10, 2) NOT NULL, -- Total booking amount
	CONSTRAINT bookings_pkey PRIMARY KEY (book_ref)
);
COMMENT ON TABLE bookings.bookings IS 'Bookings';

-- Column comments

COMMENT ON COLUMN bookings.bookings.book_ref IS 'Booking number';
COMMENT ON COLUMN bookings.bookings.book_date IS 'Booking date';
COMMENT ON COLUMN bookings.bookings.total_amount IS 'Total booking amount';


-- bookings.flights определение

-- Drop table

-- DROP TABLE bookings.flights;

CREATE TABLE bookings.flights (
	flight_id int4 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START 1 CACHE 1 NO CYCLE) NOT NULL, -- Flight ID
	route_no text NOT NULL, -- Route number
	status text NOT NULL, -- Flight status
	scheduled_departure timestamptz NOT NULL, -- Scheduled departure time
	scheduled_arrival timestamptz NOT NULL, -- Scheduled arrival time
	actual_departure timestamptz NULL, -- Actual departure time
	actual_arrival timestamptz NULL, -- Actual arrival time
	CONSTRAINT flight_actual_check CHECK (((actual_arrival IS NULL) OR ((actual_departure IS NOT NULL) AND (actual_arrival IS NOT NULL) AND (actual_arrival > actual_departure)))),
	CONSTRAINT flight_scheduled_check CHECK ((scheduled_arrival > scheduled_departure)),
	CONSTRAINT flight_status_check CHECK ((status = ANY (ARRAY['Scheduled'::text, 'On Time'::text, 'Delayed'::text, 'Boarding'::text, 'Departed'::text, 'Arrived'::text, 'Cancelled'::text]))),
	CONSTRAINT flights_pkey PRIMARY KEY (flight_id),
	CONSTRAINT flights_route_no_scheduled_departure_key UNIQUE (route_no, scheduled_departure)
);
COMMENT ON TABLE bookings.flights IS 'Flights';

-- Column comments

COMMENT ON COLUMN bookings.flights.flight_id IS 'Flight ID';
COMMENT ON COLUMN bookings.flights.route_no IS 'Route number';
COMMENT ON COLUMN bookings.flights.status IS 'Flight status';
COMMENT ON COLUMN bookings.flights.scheduled_departure IS 'Scheduled departure time';
COMMENT ON COLUMN bookings.flights.scheduled_arrival IS 'Scheduled arrival time';
COMMENT ON COLUMN bookings.flights.actual_departure IS 'Actual departure time';
COMMENT ON COLUMN bookings.flights.actual_arrival IS 'Actual arrival time';


-- bookings.routes определение

-- Drop table

-- DROP TABLE bookings.routes;

CREATE TABLE bookings.routes (
	route_no text NOT NULL, -- Route number
	validity tstzrange NOT NULL, -- Period of validity
	departure_airport bpchar(3) NOT NULL, -- Airport of departure
	arrival_airport bpchar(3) NOT NULL, -- Airport of arrival
	airplane_code bpchar(3) NOT NULL, -- Airplane code, IATA
	days_of_week _int4 NOT NULL, -- Days of week array
	scheduled_time time NOT NULL, -- Scheduled local time of departure
	duration interval NOT NULL, -- Estimated duration
	CONSTRAINT routes_route_no_validity_excl EXCLUDE USING gist (route_no WITH =, validity WITH &&),
	CONSTRAINT routes_airplane_code_fkey FOREIGN KEY (airplane_code) REFERENCES bookings.airplanes_data(airplane_code),
	CONSTRAINT routes_arrival_airport_fkey FOREIGN KEY (arrival_airport) REFERENCES bookings.airports_data(airport_code),
	CONSTRAINT routes_departure_airport_fkey FOREIGN KEY (departure_airport) REFERENCES bookings.airports_data(airport_code)
);
CREATE INDEX routes_departure_airport_lower_idx ON bookings.routes USING btree (departure_airport, lower(validity));
CREATE INDEX routes_route_no_validity_excl ON bookings.routes USING gist (route_no, validity);
COMMENT ON TABLE bookings.routes IS 'Routes';

-- Column comments

COMMENT ON COLUMN bookings.routes.route_no IS 'Route number';
COMMENT ON COLUMN bookings.routes.validity IS 'Period of validity';
COMMENT ON COLUMN bookings.routes.departure_airport IS 'Airport of departure';
COMMENT ON COLUMN bookings.routes.arrival_airport IS 'Airport of arrival';
COMMENT ON COLUMN bookings.routes.airplane_code IS 'Airplane code, IATA';
COMMENT ON COLUMN bookings.routes.days_of_week IS 'Days of week array';
COMMENT ON COLUMN bookings.routes.scheduled_time IS 'Scheduled local time of departure';
COMMENT ON COLUMN bookings.routes.duration IS 'Estimated duration';


-- bookings.seats определение

-- Drop table

-- DROP TABLE bookings.seats;

CREATE TABLE bookings.seats (
	airplane_code bpchar(3) NOT NULL, -- Airplane code, IATA
	seat_no text NOT NULL, -- Seat number
	fare_conditions text NOT NULL, -- Travel class
	CONSTRAINT seat_fare_conditions_check CHECK ((fare_conditions = ANY (ARRAY['Economy'::text, 'Comfort'::text, 'Business'::text]))),
	CONSTRAINT seats_pkey PRIMARY KEY (airplane_code, seat_no),
	CONSTRAINT seats_airplane_code_fkey FOREIGN KEY (airplane_code) REFERENCES bookings.airplanes_data(airplane_code) ON DELETE CASCADE
);
COMMENT ON TABLE bookings.seats IS 'Seats';

-- Column comments

COMMENT ON COLUMN bookings.seats.airplane_code IS 'Airplane code, IATA';
COMMENT ON COLUMN bookings.seats.seat_no IS 'Seat number';
COMMENT ON COLUMN bookings.seats.fare_conditions IS 'Travel class';


-- bookings.tickets определение

-- Drop table

-- DROP TABLE bookings.tickets;

CREATE TABLE bookings.tickets (
	ticket_no text NOT NULL, -- Ticket number
	book_ref bpchar(6) NOT NULL, -- Booking number
	passenger_id text NOT NULL, -- Passenger ID
	passenger_name text NOT NULL, -- Passenger name
	outbound bool NOT NULL, -- Outbound flight?
	CONSTRAINT tickets_book_ref_passenger_id_outbound_key UNIQUE (book_ref, passenger_id, outbound),
	CONSTRAINT tickets_pkey PRIMARY KEY (ticket_no),
	CONSTRAINT tickets_book_ref_fkey FOREIGN KEY (book_ref) REFERENCES bookings.bookings(book_ref)
);
COMMENT ON TABLE bookings.tickets IS 'Tickets';

-- Column comments

COMMENT ON COLUMN bookings.tickets.ticket_no IS 'Ticket number';
COMMENT ON COLUMN bookings.tickets.book_ref IS 'Booking number';
COMMENT ON COLUMN bookings.tickets.passenger_id IS 'Passenger ID';
COMMENT ON COLUMN bookings.tickets.passenger_name IS 'Passenger name';
COMMENT ON COLUMN bookings.tickets.outbound IS 'Outbound flight?';


-- bookings.segments определение

-- Drop table

-- DROP TABLE bookings.segments;

CREATE TABLE bookings.segments (
	ticket_no text NOT NULL, -- Ticket number
	flight_id int4 NOT NULL, -- Flight ID
	fare_conditions text NOT NULL, -- Travel class
	price numeric(10, 2) NOT NULL, -- Travel price
	CONSTRAINT segments_fare_conditions_check CHECK ((fare_conditions = ANY (ARRAY['Economy'::text, 'Comfort'::text, 'Business'::text]))),
	CONSTRAINT segments_pkey PRIMARY KEY (ticket_no, flight_id),
	CONSTRAINT segments_price_check CHECK ((price >= (0)::numeric)),
	CONSTRAINT segments_flight_id_fkey FOREIGN KEY (flight_id) REFERENCES bookings.flights(flight_id),
	CONSTRAINT segments_ticket_no_fkey FOREIGN KEY (ticket_no) REFERENCES bookings.tickets(ticket_no)
);
CREATE INDEX segments_flight_id_idx ON bookings.segments USING btree (flight_id);
COMMENT ON TABLE bookings.segments IS 'Flight segment (leg)';

-- Column comments

COMMENT ON COLUMN bookings.segments.ticket_no IS 'Ticket number';
COMMENT ON COLUMN bookings.segments.flight_id IS 'Flight ID';
COMMENT ON COLUMN bookings.segments.fare_conditions IS 'Travel class';
COMMENT ON COLUMN bookings.segments.price IS 'Travel price';


-- bookings.boarding_passes определение

-- Drop table

-- DROP TABLE bookings.boarding_passes;

CREATE TABLE bookings.boarding_passes (
	ticket_no text NOT NULL, -- Ticket number
	flight_id int4 NOT NULL, -- Flight ID
	seat_no text NOT NULL, -- Seat number
	boarding_no int4 NULL, -- Boarding pass number
	boarding_time timestamptz NULL, -- Boarding time
	CONSTRAINT boarding_passes_flight_id_boarding_no_key UNIQUE (flight_id, boarding_no),
	CONSTRAINT boarding_passes_flight_id_seat_no_key UNIQUE (flight_id, seat_no),
	CONSTRAINT boarding_passes_pkey PRIMARY KEY (ticket_no, flight_id),
	CONSTRAINT boarding_passes_ticket_no_flight_id_fkey FOREIGN KEY (ticket_no,flight_id) REFERENCES bookings.segments(ticket_no,flight_id)
);
COMMENT ON TABLE bookings.boarding_passes IS 'Boarding passes';

-- Column comments

COMMENT ON COLUMN bookings.boarding_passes.ticket_no IS 'Ticket number';
COMMENT ON COLUMN bookings.boarding_passes.flight_id IS 'Flight ID';
COMMENT ON COLUMN bookings.boarding_passes.seat_no IS 'Seat number';
COMMENT ON COLUMN bookings.boarding_passes.boarding_no IS 'Boarding pass number';
COMMENT ON COLUMN bookings.boarding_passes.boarding_time IS 'Boarding time';


-- bookings.airplanes исходный текст

CREATE OR REPLACE VIEW bookings.airplanes
AS SELECT airplane_code,
    model ->> lang() AS model,
    range,
    speed
   FROM airplanes_data ml;

COMMENT ON VIEW bookings.airplanes IS 'Airplanes';
COMMENT ON COLUMN bookings.airplanes.airplane_code IS 'Airplane code, IATA';
COMMENT ON COLUMN bookings.airplanes.model IS 'Airplane model';
COMMENT ON COLUMN bookings.airplanes."range" IS 'Maximum flight range, km';
COMMENT ON COLUMN bookings.airplanes.speed IS 'Cruise speed, km/h';


-- bookings.airports исходный текст

CREATE OR REPLACE VIEW bookings.airports
AS SELECT airport_code,
    airport_name ->> lang() AS airport_name,
    city ->> lang() AS city,
    country ->> lang() AS country,
    coordinates,
    timezone
   FROM airports_data ml;

COMMENT ON VIEW bookings.airports IS 'Airports';
COMMENT ON COLUMN bookings.airports.airport_code IS 'Airport code, IATA';
COMMENT ON COLUMN bookings.airports.airport_name IS 'Airport name';
COMMENT ON COLUMN bookings.airports.city IS 'City';
COMMENT ON COLUMN bookings.airports.country IS 'Country';
COMMENT ON COLUMN bookings.airports.coordinates IS 'Airport coordinates (longitude and latitude)';
COMMENT ON COLUMN bookings.airports.timezone IS 'Airport time zone';


-- bookings.timetable исходный текст

CREATE OR REPLACE VIEW bookings.timetable
AS SELECT f.flight_id,
    f.route_no,
    r.departure_airport,
    r.arrival_airport,
    f.status,
    r.airplane_code,
    f.scheduled_departure,
    (f.scheduled_departure AT TIME ZONE dep.timezone) AS scheduled_departure_local,
    f.actual_departure,
    (f.actual_departure AT TIME ZONE dep.timezone) AS actual_departure_local,
    f.scheduled_arrival,
    (f.scheduled_arrival AT TIME ZONE arr.timezone) AS scheduled_arrival_local,
    f.actual_arrival,
    (f.actual_arrival AT TIME ZONE arr.timezone) AS actual_arrival_local
   FROM flights f
     JOIN routes r ON r.route_no = f.route_no AND r.validity @> f.scheduled_departure
     JOIN airports_data dep ON dep.airport_code = r.departure_airport
     JOIN airports_data arr ON arr.airport_code = r.arrival_airport;

COMMENT ON VIEW bookings.timetable IS 'Detailed info about flights';
COMMENT ON COLUMN bookings.timetable.flight_id IS 'Flight ID';
COMMENT ON COLUMN bookings.timetable.route_no IS 'Route number';
COMMENT ON COLUMN bookings.timetable.departure_airport IS 'Airport of departure';
COMMENT ON COLUMN bookings.timetable.arrival_airport IS 'Airport of arrival';
COMMENT ON COLUMN bookings.timetable.status IS 'Flight status';
COMMENT ON COLUMN bookings.timetable.airplane_code IS 'Airplane code, IATA';
COMMENT ON COLUMN bookings.timetable.scheduled_departure IS 'Scheduled departure time';
COMMENT ON COLUMN bookings.timetable.scheduled_departure_local IS 'Scheduled departure time in airport''s timezone';
COMMENT ON COLUMN bookings.timetable.actual_departure IS 'Actual departure time';
COMMENT ON COLUMN bookings.timetable.actual_departure_local IS 'Actual departure time in airport''s timezone';
COMMENT ON COLUMN bookings.timetable.scheduled_arrival IS 'Scheduled arrival time';
COMMENT ON COLUMN bookings.timetable.scheduled_arrival_local IS 'Scheduled arrival time in airport''s timezone';
COMMENT ON COLUMN bookings.timetable.actual_arrival IS 'Actual arrival time';
COMMENT ON COLUMN bookings.timetable.actual_arrival_local IS 'Actual arrival time in airport''s timezone';



-- DROP FUNCTION bookings.lang();

CREATE OR REPLACE FUNCTION bookings.lang()
 RETURNS text
 LANGUAGE sql
 STABLE
RETURN current_setting('bookings.lang'::text, true)
;

COMMENT ON FUNCTION bookings.lang() IS 'Language code for translatable names';

-- DROP FUNCTION bookings.now();

CREATE OR REPLACE FUNCTION bookings.now()
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
RETURN '2027-09-01 03:00:00+03'::timestamp with time zone
;

COMMENT ON FUNCTION bookings.now() IS 'Current moment for the generated data';

-- DROP FUNCTION bookings."version"();

CREATE OR REPLACE FUNCTION bookings.version()
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
RETURN 'PostgresPro 2025-09-01 (730 days)'::text
;
