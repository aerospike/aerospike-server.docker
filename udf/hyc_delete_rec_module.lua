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
	if vmdkid == -1 or ckpt_id == -1 or offset == -1 or count ~= 3 then
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
	trace("HYC_UDF key_bin value is : %s", tostring(rec['key_bin']));

	local vals = split(tostring(rec['key_bin']), ":")
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
	if vmdkid == -1 or ckpt_id == -1 or offset == -1 or count ~= 3 then
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
