RSpec.shared_examples "a Commerce7 paginated resource" do |method:, path:, response_key:|
  let(:full_page) { Array.new(Commerce7::Client::PAGE_SIZE) { |i| { "id" => "rec-#{i}" } } }

  it "yields each record across all pages" do
    stub_request(:get, "https://api.commerce7.com/v1#{path}")
      .with(query: hash_including("page" => "1"))
      .to_return(status: 200, body: { response_key => full_page }.to_json, headers: json_headers)
    stub_request(:get, "https://api.commerce7.com/v1#{path}")
      .with(query: hash_including("page" => "2"))
      .to_return(status: 200, body: { response_key => [ { "id" => "last" } ] }.to_json, headers: json_headers)

    results = []
    client.public_send(method) { |record| results << record }

    expect(results.size).to eq(Commerce7::Client::PAGE_SIZE + 1)
    expect(results.last).to eq({ "id" => "last" })
  end

  it "returns an Enumerator when no block is given" do
    stub_request(:get, "https://api.commerce7.com/v1#{path}")
      .with(query: hash_including("page" => "1"))
      .to_return(status: 200, body: { response_key => [ { "id" => "only" } ] }.to_json, headers: json_headers)

    enum = client.public_send(method)

    expect(enum).to be_an(Enumerator)
    expect(enum.to_a).to eq([ { "id" => "only" } ])
  end
end
