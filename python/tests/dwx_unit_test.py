
from api.dwx_client import dwx_client
import sys
import json
import unittest
from time import sleep
from threading import Thread
from os.path import join, exists
from traceback import print_exc
from random import random
from datetime import datetime, timezone, timedelta

sys.path.append('../')


"""

Tests to check that the dwx_client is working correctly.  

Please don't run this on your live account. It will open and close positions!

The MT4/5 server must be initialized with MaximumOrders>=5 and MaximumLotSize>=0.02. 


sometimes it could fail if for example there is a requote, so we execute the close function as long as there are open positions. 
2021.01.14 08:47:41.664	DWX_Server_MT5 (EURUSD,D1)	CTrade::OrderSend: instant sell 0.01 position #829507488 EURUSD at 1.21442 [requote (1.21445/1.21447)]
2021.01.14 08:47:46.582	DWX_Server_MT5 (EURUSD,D1)	CTrade::OrderSend: instant sell 0.01 position #829507484 EURUSD at 1.21443 [requote (1.21445/1.21447)]
2021.01.14 08:47:46.793	DWX_Server_MT5 (EURUSD,D1)	ERROR: CLOSE_ORDER_ALL | Error during closing of 2 orders.


"""


class TestDWXConnect(unittest.TestCase):

    """Initializes dwx_client and closes all open orders. 
    """

    def setUp(self):

        self.MT4_directory_path = 'C:/Users/Administrator/AppData/Roaming/MetaQuotes/Terminal/3B534B10135CFEDF8CD1AAB8BD994B13/MQL4/Files/'

        self.symbol = 'EURUSD'
        self.magic_number = 0
        self.num_open_orders = 5
        self.lots = 0.02  # 0.02 so that we can also test partial closing.
        self.SL_and_TP_offset = 0.01
        self.types = ['buy', 'sell', 'buylimit',
                      'selllimit', 'buystop', 'sellstop']

        self.dwx = dwx_client(None, self.MT4_directory_path, sleep_delay=0.005,
                              max_retry_command_seconds=10, verbose=False)
        sleep(1)

        # make sure there are no open orders when starting the test.
        if not self.close_all_orders():
            self.fail('Could not close orders in __init__().')

    """Opens multiple orders. 

    As long as not enough orders are open, it will send new 
    open_order() commands. This is needed because of possible 
    requotes or other errors during opening of an order. 
    """

    def open_multiple_orders(self):

        for i in range(self.num_open_orders):
            self.dwx.open_order(symbol=self.symbol, order_type='buy',
                                lots=self.lots, price=0, stop_loss=0, take_profit=0,
                                magic=self.magic_number, comment='', expiration=0)
        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=10):
            sleep(1)
            now = datetime.now(timezone.utc)
            if len(self.dwx.open_orders) >= self.num_open_orders:
                return True
            # in case there was a requote, try again:
            self.dwx.open_order(symbol=self.symbol, order_type='buy',
                                lots=self.lots, price=0, stop_loss=0, take_profit=0,
                                magic=self.magic_number, comment='', expiration=0)
        return False

    """Closes all open orders. 

    As long as there are open orers, it will send new 
    close_all_orders() commands. This is needed because of 
    possible requotes or other errors during closing of an 
    order. 
    """

    def close_all_orders(self):

        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=10):
            # sometimes it could fail if for example there is a requote. so just try again.
            self.dwx.close_all_orders()
            sleep(1)
            now = datetime.now(timezone.utc)
            # print(self.dwx.open_orders)
            if len(self.dwx.open_orders) == 0:
                return True

        return False

    """Subscribes to the test symbol. 
    """

    def subscribe_symbols(self):

        self.dwx.subscribe_symbols([self.symbol])
        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=5):
            now = datetime.now(timezone.utc)
            try:
                bid = self.dwx.market_data[self.symbol]['bid']
                break
            except:
                bid = None
            sleep(0.1)

        self.assertIsInstance(bid, float)

    """Checks if there are open orders for each order type. 
    """

    def all_types_open(self):
        types_open = []
        for ticket, order in self.dwx.open_orders.items():
            types_open.append(order['type'])

        # print(types_open)
        return all(t in types_open for t in self.types)

    """Tries to open an order for each type that is not already open. 
    """

    def open_missing_types(self):
        bid = self.dwx.market_data[self.symbol]['bid']
        prices = [0, 0, bid-self.SL_and_TP_offset, bid+self.SL_and_TP_offset,
                  bid+self.SL_and_TP_offset, bid-self.SL_and_TP_offset]
        types_open = []
        for ticket, order in self.dwx.open_orders.items():
            types_open.append(order['type'])
        for i in range(len(self.types)):
            if self.types[i] in types_open:
                continue
            self.dwx.open_order(symbol=self.symbol, order_type=self.types[i],
                                lots=self.lots, price=prices[i], stop_loss=0, take_profit=0,
                                magic=self.magic_number, comment='', expiration=0)

    """Opens at least one order for each possible order type.

    It calls open_missing_types() until at least one order is open 
    for each possible order type.
    """

    def open_orders(self):

        ato = False
        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=5):
            self.open_missing_types()
            sleep(1)
            now = datetime.now(timezone.utc)
            # print(self.dwx.open_orders)
            ato = self.all_types_open()
            if ato:
                break

        self.assertTrue(ato)
        return ato

    """Modifies all open orders. 

    It will try to set the SL and TP for all open orders. 
    """

    def modify_orders(self):

        for ticket, order in self.dwx.open_orders.items():
            if 'buy' in order['type']:
                sl = order['open_price'] - self.SL_and_TP_offset
                tp = order['open_price'] + self.SL_and_TP_offset
            else:
                sl = order['open_price'] + self.SL_and_TP_offset
                tp = order['open_price'] - self.SL_and_TP_offset
            self.dwx.modify_order(ticket, lots=self.lots, price=0,
                                  stop_loss=sl,
                                  take_profit=tp,
                                  expiration=0)

        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=5):
            now = datetime.now(timezone.utc)
            all_set = True
            for ticket, order in self.dwx.open_orders.items():
                if order['TP'] <= 0 or order['SL'] <= 0:
                    all_set = False
            if all_set:
                break
            sleep(0.1)
        self.assertTrue(all_set)
        return all_set

    """Tries to close an one order. 

    This could fail if the closing of an orders takes too long and 
    then two orders might be closed. 
    """

    def close_order(self):

        if len(self.dwx.open_orders) == 0:
            self.fail('There are no order to close in close_order().')

        ticket = list(self.dwx.open_orders.keys())[0]

        num_orders_before = len(self.dwx.open_orders)

        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=5):
            self.dwx.close_order(ticket, lots=0)
            sleep(1)
            now = datetime.now(timezone.utc)
            try:
                num_orders = len(self.dwx.open_orders)
                if num_orders == num_orders_before-1:
                    break
            except:
                num_orders = None

        self.assertEqual(num_orders, num_orders_before-1)

    """Tries to partially close an order. 
    """

    def close_order_partial(self):

        if len(self.dwx.open_orders) == 0:
            self.fail('There are no order to close in close_order_partial().')

        close_lots = 0.01

        ticket = None
        for t in self.dwx.open_orders.keys():
            if self.dwx.open_orders[t]['type'] == 'buy':
                ticket = t
                break

        self.assertTrue(ticket is not None)

        lots_before = self.dwx.open_orders[ticket]['lots']
        self.assertTrue(lots_before > 0)

        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=5):
            self.dwx.close_order(ticket, lots=close_lots)
            sleep(2)
            now = datetime.now(timezone.utc)
            try:
                # need to loop because the ticket will change after modification.
                found = False
                for ticket, order in self.dwx.open_orders.items():
                    lots = order['lots']
                    if abs(lots_before - close_lots - lots) < 0.001:
                        found = True
                        break
                if found:
                    break
            except:
                lots = None

        self.assertTrue(lots > 0)
        self.assertTrue(abs(lots_before - close_lots - lots) < 0.001)

    """Tests the try_read_file() function by reading 
    the file where open orders are stored. 
    """

    def test_try_read_file(self):
        result = self.dwx.try_read_file(
            join(self.MT4_directory_path, 'DWX', 'DWX_Orders.txt'))
        result = json.loads(result)
        self.assertIsInstance(result, dict)

    """Tests the test_load_orders(). 
    """

    def test_load_orders(self):
        result = self.dwx.load_orders()
        self.assertIsNone(result)

    """Tests the test_load_messages(). 
    """

    def test_load_messages(self):
        result = self.dwx.load_messages()
        self.assertIsNone(result)

    """Tests subscribing to a symbol, opening, modifying, closing 
    and partial closing of orders. 

    Combined to one test function because these tests have to be 
    executed in the correct order. 
    """

    def test_open_modify_close_order(self):
        print('test_open_modify_close_order')

        if not self.close_all_orders():
            self.fail('Could not close orders in test_open_modify_close_order().')

        # need to be subscirbed to get the current bid.
        self.subscribe_symbols()

        if not self.open_orders():
            self.fail('open_orders() returned false.')

        # print(len(self.dwx.open_orders))
        # print(self.dwx.open_orders)

        if not self.modify_orders():
            self.fail('modify_orders() returned false.')

        # print(len(self.dwx.open_orders))
        # print(self.dwx.open_orders)

        self.close_order()

        self.close_order_partial()

        # print(len(self.dwx.open_orders))
        # print(self.dwx.open_orders)

        if not self.close_all_orders():
            self.fail(
                'Could not close orders after test_open_modify_close_order().')

    """Tests to close all open orders. 

    First it will try to open multiple orders. 
    """

    def test_close_all_orders(self):
        print('test_close_all_orders')

        if not self.open_multiple_orders():
            self.fail('Could not open all orders in test_close_all_orders().')

        self.assertTrue(self.close_all_orders())

    """Tests to close all orders with a given symbol. 

    First it will try to open multiple orders. 
    """

    def test_close_orders_by_symbol(self):
        print('test_close_orders_by_symbol')

        if not self.open_multiple_orders():
            self.fail(
                'Could not open all orders in test_close_orders_by_symbol().')

        self.dwx.close_orders_by_symbol(self.symbol)
        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=10):
            sleep(1)
            now = datetime.now(timezone.utc)
            if len(self.dwx.open_orders) == 0:
                break
            self.dwx.close_orders_by_symbol(self.symbol)
        self.assertEqual(len(self.dwx.open_orders), 0)

    """Tests to close all orders with a given magic number. 

    First it will try to open multiple orders. 
    """

    def test_close_orders_by_magic(self):
        print('test_close_orders_by_magic')

        if not self.open_multiple_orders():
            self.fail(
                'Could not open all orders in test_close_orders_by_magic().')

        self.dwx.close_orders_by_magic(self.magic_number)
        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=10):
            sleep(1)
            now = datetime.now(timezone.utc)
            if len(self.dwx.open_orders) == 0:
                break
            self.dwx.close_orders_by_magic(self.magic_number)
        self.assertEqual(len(self.dwx.open_orders), 0)

    """Tests the subscribe_symbols_bar_data() function. 
    """

    def test_subscribe_symbols_bar_data(self):
        time_frame = 'M1'
        self.dwx.subscribe_symbols_bar_data([[self.symbol, time_frame]])
        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=5):
            sleep(0.1)
            now = datetime.now(timezone.utc)
            try:
                # no need to check the length since it would trigger an exception if not found.
                bar_data = self.dwx.bar_data[self.symbol + '_' + time_frame]
                # print(bar_data)
                break
            except:
                bar_data = None
        self.assertIsInstance(bar_data, dict)

    """Tests the get_historic_data() function. 
    """

    def test_get_historic_data(self):

        time_frame = 'D1'
        self.dwx.get_historic_data(self.symbol, time_frame=time_frame,
                                   start=(datetime.now(timezone.utc) -
                                          timedelta(days=30)).timestamp(),
                                   end=datetime.now(timezone.utc).timestamp())
        start_time = datetime.now(timezone.utc)
        now = datetime.now(timezone.utc)
        while now < start_time + timedelta(seconds=5):
            sleep(0.1)
            now = datetime.now(timezone.utc)
            try:
                historic_data = self.dwx.historic_data[self.symbol +
                                                       '_' + time_frame]
                # print(historic_data)
                break
            except:
                historic_data = None
        self.assertIsInstance(historic_data, dict)


if __name__ == '__main__':
    unittest.main()
