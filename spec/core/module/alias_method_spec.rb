require File.dirname(__FILE__) + '/../../spec_helper'
require File.dirname(__FILE__) + '/fixtures/classes'

describe "Module#alias_method" do

  before(:each) do
    @class = Class.new(ModuleSpecs::Aliasing)
    @object = @class.new 
  end
  
  it "makes a copy of the method" do
    @class.make_alias :uno, :public_one
    @class.make_alias :double, :public_two
    @object.uno.should == @object.public_one
    @object.double(12).should == @object.public_two(12)
  end

  it "retains method visibility" do
    @class.make_alias :private_ichi, :private_one
    should_raise(NameError) { @object.private_one }
    should_raise(NameError) { @object.private_ichi }
    @class.make_alias :public_ichi, :public_one
    @object.public_ichi.should == @object.public_one
    @class.make_alias :protected_ichi, :protected_one
    should_raise(NameError) { @object.protected_ichi }
  end
  
  it "fails if origin method not found" do
    should_raise(NameError) do
      @class.make_alias :ni, :san
    end
  end

  it "converts a non string/symbol/fixnum name to string using to_str" do
    @class.make_alias "un", "public_one"
    @class.make_alias :deux, "public_one"
    @class.make_alias "trois", :public_one
    @class.make_alias :quatre, :public_one
    name = Object.new
    name.should_receive(:to_str, :returning => "cinq")
    @class.make_alias name, "public_one"
    name.should_receive(:to_str, :returning => "public_one")
    @class.make_alias "cinq", name
  end

  it "raises TypeError when the given name can't be converted using to_str" do
    should_raise(TypeError) do
      @class.make_alias Object.new, :public_one
    end
  end

  it "is a private method" do
    should_raise(NoMethodError) do
      @class.alias_method :ichi, :public_one
    end
  end
  
end

