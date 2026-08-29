import unittest
from unittest import mock

import requests

import lhasa


def response(status_code, url="https://example.test/data"):
    result = mock.MagicMock(spec=requests.Response)
    result.status_code = status_code
    result.url = url
    result.ok = status_code < 400
    result.__enter__.return_value = result
    return result


class HttpRequestTests(unittest.TestCase):
    @mock.patch("lhasa.time.sleep")
    def test_latest_imerg_time_retries_tls_failure(self, sleep):
        unavailable = response(404)
        available = response(200)

        with mock.patch.object(
            lhasa.HTTP_SESSION,
            "get",
            side_effect=[
                requests.exceptions.SSLError("temporary"),
                unavailable,
                available,
            ],
        ) as get:
            latest = lhasa.get_latest_imerg_time()

        self.assertIsNotNone(latest)
        self.assertEqual(get.call_count, 3)
        self.assertEqual(sleep.call_args_list, [mock.call(1.0)])
        for call in get.call_args_list:
            self.assertEqual(call.kwargs["timeout"], lhasa.HTTP_TIMEOUT)

    @mock.patch("lhasa.time.sleep")
    def test_request_retries_temporary_server_error(self, sleep):
        busy = response(503)
        available = response(200)

        with mock.patch.object(
            lhasa.HTTP_SESSION,
            "get",
            side_effect=[busy, available],
        ) as get:
            result = lhasa.get_with_retry("https://example.test/data")

        self.assertIs(result, available)
        self.assertEqual(get.call_count, 2)
        self.assertEqual(sleep.call_args_list, [mock.call(1.0)])

    @mock.patch("lhasa.time.sleep")
    def test_request_stops_after_attempt_limit(self, sleep):
        with mock.patch.object(
            lhasa.HTTP_SESSION,
            "get",
            side_effect=requests.exceptions.Timeout("temporary"),
        ) as get:
            with self.assertRaises(requests.exceptions.Timeout):
                lhasa.get_with_retry("https://example.test/data")

        self.assertEqual(get.call_count, lhasa.HTTP_MAX_ATTEMPTS)
        self.assertEqual(
            sleep.call_args_list,
            [mock.call(1.0), mock.call(2.0), mock.call(4.0), mock.call(8.0)],
        )


if __name__ == "__main__":
    unittest.main()
