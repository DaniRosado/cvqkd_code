# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "C_S_AXI_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "C_S_AXI_DATA_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TOTAL_BLOCKS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "W" -parent ${Page_0}
  ipgui::add_param $IPINST -name "Z" -parent ${Page_0}


}

proc update_PARAM_VALUE.C_S_AXI_ADDR_WIDTH { PARAM_VALUE.C_S_AXI_ADDR_WIDTH } {
	# Procedure called to update C_S_AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S_AXI_ADDR_WIDTH { PARAM_VALUE.C_S_AXI_ADDR_WIDTH } {
	# Procedure called to validate C_S_AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S_AXI_DATA_WIDTH { PARAM_VALUE.C_S_AXI_DATA_WIDTH } {
	# Procedure called to update C_S_AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S_AXI_DATA_WIDTH { PARAM_VALUE.C_S_AXI_DATA_WIDTH } {
	# Procedure called to validate C_S_AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.TOTAL_BLOCKS { PARAM_VALUE.TOTAL_BLOCKS } {
	# Procedure called to update TOTAL_BLOCKS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TOTAL_BLOCKS { PARAM_VALUE.TOTAL_BLOCKS } {
	# Procedure called to validate TOTAL_BLOCKS
	return true
}

proc update_PARAM_VALUE.W { PARAM_VALUE.W } {
	# Procedure called to update W when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.W { PARAM_VALUE.W } {
	# Procedure called to validate W
	return true
}

proc update_PARAM_VALUE.Z { PARAM_VALUE.Z } {
	# Procedure called to update Z when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.Z { PARAM_VALUE.Z } {
	# Procedure called to validate Z
	return true
}


proc update_MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH PARAM_VALUE.C_S_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S_AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH PARAM_VALUE.C_S_AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S_AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.TOTAL_BLOCKS { MODELPARAM_VALUE.TOTAL_BLOCKS PARAM_VALUE.TOTAL_BLOCKS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TOTAL_BLOCKS}] ${MODELPARAM_VALUE.TOTAL_BLOCKS}
}

proc update_MODELPARAM_VALUE.Z { MODELPARAM_VALUE.Z PARAM_VALUE.Z } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.Z}] ${MODELPARAM_VALUE.Z}
}

proc update_MODELPARAM_VALUE.W { MODELPARAM_VALUE.W PARAM_VALUE.W } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.W}] ${MODELPARAM_VALUE.W}
}

