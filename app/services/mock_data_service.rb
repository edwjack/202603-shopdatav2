class MockDataService
  FIXTURES_PATH = Rails.root.join('test/fixtures/files')

  def self.load(fixture_name)
    file = FIXTURES_PATH.join("#{fixture_name}.json")
    JSON.parse(File.read(file))
  end

  def self.mock_mode?
    ENV['MOCK_EXTERNAL_APIS'] == 'true'
  end
end
