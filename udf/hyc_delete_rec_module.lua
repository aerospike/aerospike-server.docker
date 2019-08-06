local function split(str, sep)
	local result = {}
	local regex = ("([^%s]+)"):format(sep)
	for each in str:gmatch(regex) do
		table.insert(result, each)
	end

	return result
end

function hyc_delete_rec(rec, input_ids)
	trace("HYC_UDF args:: (%s)--------------------", tostring(input_ids));
	trace("HYC_UDF key:: (%s)--------------------", record.key(rec));

	local rec_vmdkid = -1; rec_ckptid = -1; rec_offset = -1
	local vals = split(record.key(rec), ":")
	local count = 0
	for _,val in ipairs(vals) do
		if count == 0 then
			rec_vmdkid = tonumber(val)
		elseif count == 1 then
			rec_ckptid = tonumber(val)
		elseif count == 2 then
			rec_offset = tonumber(val)
		end

		count = count + 1
	end

	trace("HYC_UDF Post split count : %d, vmdkid : %d, ckpt_id : %d, offset :%d", count, rec_vmdkid, rec_ckptid, rec_offset);
	if rec_vmdkid == -1 or rec_ckptid == -1 or rec_offset == -1 or count ~= 3 then
		trace("HYC_UDF Error, Invalid record format");
	else
		local elem
		local result
		local input_vmdkid = -1; input_ckptid = -1
		for elm in list.iterator(input_ids) do
			result = split(elm, ":")
			trace("HYC_UDF result:: (%s)--------------------", tostring(result));
			count = 0
			for _,val in ipairs(result) do
				if count == 0 then
					input_vmdkid = tonumber(val)
				elseif count == 1 then
					input_ckptid = tonumber(val)
				end
				count = count + 1
			end
			trace("HYC_UDF input_vmdkid: %d rec_vmdkid: %d", tonumber(input_vmdkid), tonumber(rec_vmdkid));
			trace("HYC_UDF input_ckptid: %d rec_ckptid: %d", tonumber(input_ckptid), tonumber(rec_ckptid));

			if rec_vmdkid == input_vmdkid and (input_ckptid == 0 or rec_ckptid == input_ckptid) then
				trace("HYC_UDF found match ckpt ID :: %d, offset : %d", tonumber(rec_ckptid), rec_offset);
				aerospike:remove(rec)
			end
		end
	end
end

function hyc_delete_rec_bin_ext(rec, input_ids)

	trace("HYC_UDF args:: (%s)--------------------", tostring(input_ids));
	trace("HYC_UDF key:: (%s)--------------------", record.key(rec));

	names = record.bin_names(rec)
	for i, name in ipairs(names) do
		trace("HYC_UDF bin %d name = %s", i, tostring(name))
	end

	local rec_vmdkid = -1; rec_ckptid = -1; rec_offset = -1
	trace("HYC_UDF key_bin value is : %s", tostring(rec['Key']));

	local vals = split(tostring(rec['Key']), ":")
	local count = 0
	for _,val in ipairs(vals) do
		if count == 0 then
			rec_vmdkid = tonumber(val)
		elseif count == 1 then
			rec_ckptid = tonumber(val)
		elseif count == 2 then
			rec_offset = tonumber(val)
		end

		count = count + 1
	end

	trace("HYC_UDF Post split count : %d, vmdkid : %d, ckpt_id : %d, offset :%d", count, rec_vmdkid, rec_ckptid, rec_offset);
	if rec_vmdkid == -1 or rec_ckptid == -1 or rec_offset == -1 or count ~= 3 then
		trace("HYC_UDF Error, Invalid record format");
	else
		local elem
		local result
		local input_vmdkid = -1; input_ckptid = -1
		for elm in list.iterator(input_ids) do
			result = split(elm, ":")
			trace("HYC_UDF result:: (%s)--------------------", tostring(result));
			count = 0
			for _,val in ipairs(result) do
				if count == 0 then
					input_vmdkid = tonumber(val)
				elseif count == 1 then
					input_ckptid = tonumber(val)
				end
				count = count + 1
			end
			trace("HYC_UDF input_vmdkid: %d rec_vmdkid: %d", tonumber(input_vmdkid), tonumber(rec_vmdkid));
			trace("HYC_UDF input_ckptid: %d rec_ckptid: %d", tonumber(input_ckptid), tonumber(rec_ckptid));

			if rec_vmdkid == input_vmdkid and (input_ckptid == 0 or rec_ckptid == input_ckptid) then
				trace("HYC_UDF found match ckpt ID :: %d, offset : %d", tonumber(rec_ckptid), rec_offset);
				aerospike:remove(rec)
			end
		end
	end
end

function hyc_delete_rec_bin_ext_with_update_time(rec, input_ids)

	trace("HYC_UDF args:: (%s)--------------------", tostring(input_ids));
	trace("HYC_UDF key:: (%s)--------------------", record.key(rec));

	names = record.bin_names(rec)
	for i, name in ipairs(names) do
		trace("HYC_UDF bin %d name = %s", i, tostring(name))
	end

	local rec_vmdkid = -1; rec_ckptid = -1; rec_offset = -1; rec_timestamp = -1
	trace("HYC_UDF key_bin value is : %s", tostring(rec['Key']));

	local vals = split(tostring(rec['Key']), ":")
	local count = 0
	for _,val in ipairs(vals) do
		if count == 0 then
			rec_vmdkid = tonumber(val)
		elseif count == 1 then
			rec_ckptid = tonumber(val)
		elseif count == 2 then
			rec_offset = tonumber(val)
		end

		count = count + 1
	end

	rec_timestamp = tonumber(rec['UpdateTime'])
	trace("HYC_UDF Post split count : %d, vmdkid : %d, ckpt_id : %d, offset :%d, timestamp: %d", count, rec_vmdkid, rec_ckptid, rec_offset, rec_timestamp);
	if rec_vmdkid == -1 or rec_ckptid == -1 or rec_offset == -1 or rec_timestamp == -1 or count ~= 3 then
		trace("HYC_UDF Error, Invalid record format");
	else
		local elem
		local result
		local input_vmdkid = -1; input_ckptid = -1; input_timestamp = -1
		for elm in list.iterator(input_ids) do
			result = split(elm, ":")
			trace("HYC_UDF result:: (%s)--------------------", tostring(result));
			count = 0
			for _,val in ipairs(result) do
				if count == 0 then
					input_vmdkid = tonumber(val)
				elseif count == 1 then
					input_ckptid = tonumber(val)
				elseif count == 2 then
					input_timestamp = tonumber(val)
				end
				count = count + 1
			end
			trace("HYC_UDF input_vmdkid: %d rec_vmdkid: %d", tonumber(input_vmdkid), tonumber(rec_vmdkid));
			trace("HYC_UDF input_ckptid: %d rec_ckptid: %d", tonumber(input_ckptid), tonumber(rec_ckptid));
			trace("HYC_UDF input_ts: %d rec_ts: %d", tonumber(input_timestamp), tonumber(rec_timestamp));

			if rec_vmdkid == input_vmdkid and (input_ckptid == 0 or rec_ckptid == input_ckptid) 
					and (input_timestamp == 0 or rec_timestamp <= input_timestamp) then
				trace("HYC_UDF found match ckpt ID :: %d, offset : %d, rec_timestamp : %d", tonumber(rec_ckptid), rec_offset, rec_timestamp);
				aerospike:remove(rec)
			end
		end
	end
end
