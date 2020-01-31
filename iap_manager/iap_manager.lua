local broadcast = require("ludobits.m.broadcast")

-- Required deps:
-- https://github.com/britzl/ludobits/archive/master.zip
-- https://github.com/defold/extension-iap/archive/master.zip

-- Docs:
-- https://defold.com/extension-iap/
-- https://defold.com/manuals/iap/
-- https://github.com/britzl/ludobits/blob/master/ludobits/m/broadcast.md

local M = {}

M.VERBOSE = true

-- debug Android product ids
--[[
https://developer.android.com/google/play/billing/billing_testing
android.test.purchased
Google Play responds as though you successfully purchased an item. The response includes a JSON string, which contains fake purchase information (for example, a fake order ID).
android.test.canceled
Google Play responds as though the purchase was canceled. This can occur when an error is encountered in the order process, such as an invalid credit card, or when you cancel a user’s order before it is charged.
android.test.refunded
Google Play responds as though the purchase was refunded.
android.test.item_unavailable
Google Play responds as though the item being purchased was not listed in your application’s product list.
--]]

M.ID_ANDROID_TEST_PURCHASED = "android.test.purchased"
M.ID_ANDROID_TEST_CANCELED = "android.test.canceled"
M.ID_ANDROID_TEST_REFUNDED = "android.test.refunded"
M.ID_ANDROID_TEST_UNAVAILABLE = "android.test.item_unavailable"

M.owned_products = {} -- verified owned products
M.consumable_products = {} -- verified consumable products
M.available_products = {} -- store validated product ids
M.registered_products = {}

-- functions

local function iap_listener(self, transaction, error)
	broadcast.send("iap_listener", {transaction = transaction, error = error})

	if M.VERBOSE then 
		print("IAP Manager", "Got a Transaction!")
		pprint(transaction)
		if error then
			print("IAP Manager", "Transaction Error!")
			pprint(error)
		end
	end

	if error == nil then
		-- transaction.ident - product identifier
		-- transaction.state - see below
		-- transaction.date - date and time for transaction
		-- transaction.trans_ident - transaction identifier, only set when state is either 
			-- TRANS_STATE_RESTORED
			-- TRANS_STATE_UNVERIFIED
			-- TRANS_STATE_PURCHASED
		-- transaction.receipt - send to server to verify
		-- transaction.original_trans - Apple only when state is TRANS_STATE_RESTORED
		-- transaction.signature - Google only signature of purchase data

		
		if transaction.state == iap.TRANS_STATE_PURCHASING then
			if M.VERBOSE then print("IAP Manager", "Transaction State: Purchasing") end
		elseif transaction.state == iap.TRANS_STATE_PURCHASED then
			if M.VERBOSE then print("IAP Manager", "Transaction State: Purchased") end

			broadcast.send("iap_purchased", transaction.ident)

			if not M.consumable_products[transaction.ident] then
				M.owned_products[transaction.ident] = transaction
			else
				M.consumable_products[transaction.trans_ident] = transaction
			end

			if iap.get_provider_id() == iap.PROVIDER_ID_APPLE then -- permanent Apple products must always be finished
				if not consumable_list[transaction.ident] then
					iap.finish(transaction)
				end
			end
			
		elseif transaction.state == iap.TRANS_STATE_UNVERIFIED then
			if M.VERBOSE then print("IAP Manager", "Transaction State: Unverified") end
		elseif transaction.state == iap.TRANS_STATE_FAILED then
			if M.VERBOSE then print("IAP Manager", "Transaction State: Failed") end
		elseif transaction.state == iap.TRANS_STATE_RESTORED then
			if M.VERBOSE then print("IAP Manager", "Transaction State: Restored") end
			broadcast.send("iap_restored", transaction.ident)
		end
	else
		-- error.reason can be
		-- iap.REASON_UNSPECIFIED
		-- iap.REASON_USER_CANCELED

		if error.reason then
			broadcast.send("iap_error", error.reason)
		end

		if M.VERBOSE and error.reason == iap.REASON_USER_CANCELED then
			print("IAP Manager", "Transaction Error: User Canceled")
		end
		if M.VERBOSE and error.reason == iap.REASON_UNSPECIFIED then
			print("IAP Manager", "Transaction Error: Unspecified")
		end
		
	end	
end

function M.register_products(products)
	-- products = {
	-- 	{ ident = "com.defold.test_product", is_consumable = false},
	-- 	{ ident = "com.defold.test_consumable", is_consumable = true},
	-- }
	for k, v in pairs(products) do
		if M.VERBOSE then print("IAP Manager", "Registered product:", v.ident, "Is consumable:", v.is_consumable) end
		M.registered_products[v.ident] = v
	end
end

function M.init()
	if iap then
		iap.list({ -- max of 20 per request, if more than 20 do multiple requests
			
			-- todo
			
		},M.update_valid_product_list)
		
		iap.set_listener(iap_listener)
		iap.restore() -- only manually restore please
	end
end

function M.update_valid_product_list(self, products, error)
	if error == nil then
		for _,product in ipairs(products) do
			M.available_products[product.ident] = {}
			M.available_products[product.ident].ident = product.ident
			M.available_products[product.ident].title = product.title
			M.available_products[product.ident].description = product.description
			M.available_products[product.ident].price = product.price
			M.available_products[product.ident].price_string = product.price_string
			M.available_products[product.ident].currency_code = product.currency_code
		end
	else
		if M.VERBOSE then 
			print("IAP Manager", "iap.list error", error.error)
			broadcast.send("iap_list_error", error.error)
		end
	end
end

function M.check_if_owned(id)
	if M.owned_products[id] ~= nil then
		return true
	else
		return false
	end
end

-- Example:
-- while iap_manager.get_next_consumale() do
-- 	... process each consumable
-- end

function M.get_next_consumable()
	if not iap then return false end
	if next(M.consumable_products) ~= nil then
		local key, product = next(M.consumable_products)
		M.consumable_products[key] = nil
		iap.finish(product)
		return product
	else
		return false
	end
end


function M.restore_owned()
	if not iap then return end
	print("Attempting to restore...")
	iap.restore()
end

function M.buy(id)
	if not iap then return end
	print("Attempting to buy...", id)
	iap.buy(id)
end

function M.force_finish_all()
	if not iap then return end
	for k, v in pairs(M.owned_products) do
		iap.finish(v)
	end
	M.owned_products = {}

	for k, v in pairs(M.consumable_products) do
		iap.finish(v)
	end
	M.consumable_products = {}
	
end

function M.is_owned(ident)
	if M.owned_products[ident] then 
		return true 
	else 
		return false 
	end
end

return M